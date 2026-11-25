/*
 * Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * Call single functions of the EPANET 2.3.6 hydraulic solver on a state
 * that a command file sets, and print what they give.
 *
 *     epanet_units CASES < units.txt > units.expected
 *
 * `make_epanet_units.py` builds this program against the EPANET source,
 * with the `static` of the solver files removed so that this file can call
 * them. CASES is `cases.txt`. See `make_epanet_units.py` for the commands.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "epanet2_2.h"
#include "types.h"
#include "funcs.h"

typedef struct {
    double maxheaderror;
    double maxflowerror;
    double maxflowchange;
    int maxheadlink;
    int maxflownode;
    int maxflowlink;
} Hydbalance;

StatusType cvstatus(Project *, StatusType, double, double);
StatusType pumpstatus(Project *, int, double);
StatusType prvstatus(Project *, int, StatusType, double, double, double);
StatusType psvstatus(Project *, int, StatusType, double, double, double);
StatusType fcvstatus(Project *, int, StatusType, double, double);
int badvalve(Project *, int);
int pswitch(Project *);
void newdemandflows(Project *, Hydbalance *, double *, double *);
int hasconverged(Project *, double *, Hydbalance *);
int pdaconverged(Project *);
void demandcoeffs(Project *);
void emittercoeffs(Project *);
void pumpcoeff(Project *, int);
void pbvcoeff(Project *, int);

static char *case_text(const char *path, const char *name)
{
    FILE *f = fopen(path, "r");
    char line[4096];
    char *text = NULL;
    size_t len = 0;
    int in = 0;
    if (!f) return NULL;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "#### ", 5) == 0) {
            line[strcspn(line, "\r\n")] = 0;
            if (in) break;
            in = strcmp(line + 5, name) == 0;
            continue;
        }
        if (in) {
            size_t n = strlen(line);
            text = realloc(text, len + n + 1);
            memcpy(text + len, line, n + 1);
            len += n;
        }
    }
    fclose(f);
    return text;
}

static void print_links(Project *pr)
{
    int k;
    printf(" |");
    for (k = 1; k <= pr->network.Nlinks; k++) printf(" %d", pr->hydraul.LinkStatus[k]);
    printf(" |");
    for (k = 1; k <= pr->network.Nlinks; k++) printf(" %.17g", pr->hydraul.LinkSetting[k]);
}

static void print_rows(Project *pr)
{
    int i;
    printf(" |");
    for (i = 1; i <= pr->network.Njuncs; i++) {
        int r = pr->hydraul.smatrix.Row[i];
        printf(" %.17g %.17g", pr->hydraul.smatrix.Aii[r], pr->hydraul.smatrix.F[r]);
    }
}

static void zero_rows(Project *pr)
{
    int i;
    for (i = 0; i <= pr->network.Nnodes; i++) {
        pr->hydraul.smatrix.Aii[i] = 0.0;
        pr->hydraul.smatrix.F[i] = 0.0;
    }
}

int main(int argc, char **argv)
{
    char line[1024];
    Project *pr = NULL;
    while (fgets(line, sizeof(line), stdin)) {
        char cmd[64], what[64];
        line[strcspn(line, "\r\n")] = 0;
        if (line[0] == '#' || line[0] == 0) continue;
        if (sscanf(line, "%63s", cmd) != 1) continue;
        if (strcmp(cmd, "net") == 0) {
            char name[256];
            char *text;
            FILE *f;
            long t;
            sscanf(line, "net %255s", name);
            if (pr) EN_deleteproject(pr);
            EN_createproject(&pr);
            text = case_text(argv[1], name);
            f = fopen("units_net.inp", "w");
            fputs(text, f);
            fclose(f);
            free(text);
            /* A code of 100 or less is a warning. */
            if (EN_open(pr, "units_net.inp", "units_net.rpt", "") > 100 ||
                EN_openH(pr) > 100 || EN_initH(pr, 0) > 100 || EN_runH(pr, &t) > 100) {
                printf("%s = error\n", line);
                return 1;
            }
            printf("%s\n", line);
        } else if (strcmp(cmd, "set") == 0) {
            int i;
            double v;
            Hydraul *hyd = &pr->hydraul;
            sscanf(line, "set %63s %d %lf", what, &i, &v);
            if (strcmp(what, "flow") == 0) hyd->LinkFlow[i] = v;
            else if (strcmp(what, "head") == 0) hyd->NodeHead[i] = v;
            else if (strcmp(what, "status") == 0) hyd->LinkStatus[i] = (StatusType)(int)v;
            else if (strcmp(what, "setting") == 0) hyd->LinkSetting[i] = v;
            else if (strcmp(what, "demandflow") == 0) hyd->DemandFlow[i] = v;
            else if (strcmp(what, "fulldemand") == 0) hyd->FullDemand[i] = v;
            else if (strcmp(what, "nodedemand") == 0) hyd->NodeDemand[i] = v;
            else if (strcmp(what, "emitterflow") == 0) hyd->EmitterFlow[i] = v;
            else if (strcmp(what, "leakageflow") == 0) hyd->LeakageFlow[i] = v;
            else if (strcmp(what, "km") == 0) pr->network.Link[i].Km = v;
            else if (strcmp(what, "tankv") == 0) pr->network.Tank[i].V = v;
            else { printf("%s = unknown\n", line); return 1; }
            printf("%s\n", line);
        } else if (strcmp(cmd, "call") == 0) {
            double a[6] = {0, 0, 0, 0, 0, 0};
            int n = sscanf(line, "call %63s %lf %lf %lf %lf %lf %lf", what,
                           &a[0], &a[1], &a[2], &a[3], &a[4], &a[5]);
            printf("%s =", line);
            if (strcmp(what, "cvstatus") == 0)
                printf(" %d", cvstatus(pr, (StatusType)(int)a[0], a[1], a[2]));
            else if (strcmp(what, "pumpstatus") == 0)
                printf(" %d", pumpstatus(pr, (int)a[0], a[1]));
            else if (strcmp(what, "prvstatus") == 0)
                printf(" %d", prvstatus(pr, (int)a[0], (StatusType)(int)a[1], a[2], a[3], a[4]));
            else if (strcmp(what, "psvstatus") == 0)
                printf(" %d", psvstatus(pr, (int)a[0], (StatusType)(int)a[1], a[2], a[3], a[4]));
            else if (strcmp(what, "fcvstatus") == 0)
                printf(" %d", fcvstatus(pr, (int)a[0], (StatusType)(int)a[1], a[2], a[3]));
            else if (strcmp(what, "badvalve") == 0) {
                printf(" %d", badvalve(pr, (int)a[0]));
                print_links(pr);
            } else if (strcmp(what, "pswitch") == 0) {
                printf(" %d", pswitch(pr));
                print_links(pr);
            } else if (strcmp(what, "newdemandflows") == 0) {
                Hydbalance hb = {0, 0, 0, 0, 0, 0};
                double qsum = 0.0, dqsum = 0.0;
                int i;
                pr->hydraul.RelaxFactor = 1.0;
                newdemandflows(pr, &hb, &qsum, &dqsum);
                printf(" %.17g %.17g %.17g %d |", qsum, dqsum, hb.maxflowchange, hb.maxflownode);
                for (i = 1; i <= pr->network.Njuncs; i++) printf(" %.17g", pr->hydraul.DemandFlow[i]);
            } else if (strcmp(what, "hasconverged") == 0) {
                Hydbalance hb = {0, 0, a[1], 0, 0, 0};
                double relerr = a[0];
                printf(" %d", hasconverged(pr, &relerr, &hb));
            } else if (strcmp(what, "pdaconverged") == 0) {
                int c = pdaconverged(pr);
                printf(" %d %d %.17g", c, pr->hydraul.DeficientNodes, pr->hydraul.DemandReduction);
            } else if (strcmp(what, "leakagehasconverged") == 0)
                printf(" %d", leakagehasconverged(pr));
            else if (strcmp(what, "demandcoeffs") == 0) {
                zero_rows(pr);
                demandcoeffs(pr);
                print_rows(pr);
            } else if (strcmp(what, "emittercoeffs") == 0) {
                zero_rows(pr);
                emittercoeffs(pr);
                print_rows(pr);
            } else if (strcmp(what, "pumpcoeff") == 0) {
                pumpcoeff(pr, (int)a[0]);
                printf(" %.17g %.17g", pr->hydraul.P[(int)a[0]], pr->hydraul.Y[(int)a[0]]);
            } else if (strcmp(what, "pbvcoeff") == 0) {
                pbvcoeff(pr, (int)a[0]);
                printf(" %.17g %.17g", pr->hydraul.P[(int)a[0]], pr->hydraul.Y[(int)a[0]]);
            } else if (strcmp(what, "tanktimestep") == 0) {
                long t = (long)a[0];
                int i = tanktimestep(pr, &t);
                printf(" %d %ld", i, t);
            } else {
                printf(" unknown\n");
                return 1;
            }
            (void)n;
            printf("\n");
        }
    }
    if (pr) EN_deleteproject(pr);
    return 0;
}
