// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Build against OpenEXR 3.1.5 and Imath 3.1.5. Fixture tooling only.
#include <OpenEXR/ImfInputFile.h>
#include <OpenEXR/ImfOutputFile.h>
#include <OpenEXR/ImfHeader.h>
#include <OpenEXR/ImfChannelList.h>
#include <OpenEXR/ImfFrameBuffer.h>
#include <OpenEXR/OpenEXRConfig.h>
#include <Imath/half.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <string>
#include <vector>
using namespace OPENEXR_IMF_NAMESPACE;
struct Plane {
    PixelType type;
    bool linear;
    std::vector<char> bytes;
    Plane() = default;
    Plane(PixelType t, bool l, int n): type(t), linear(l), bytes(n*(t==HALF?2:4)) {}
    int stride() const { return type==HALF?2:4; }
    void set(int i,float v) {
        if(type==HALF){ IMATH_NAMESPACE::half h(v); std::memcpy(bytes.data()+i*2,&h,2); }
        else if(type==FLOAT) std::memcpy(bytes.data()+i*4,&v,4);
        else { unsigned u=unsigned(v*1000); std::memcpy(bytes.data()+i*4,&u,4); }
    }
};
static void decode(const std::string& path, const std::string& output) {
    InputFile f(path.c_str()); const auto& h=f.header();
    int w=h.dataWindow().max.x-h.dataWindow().min.x+1;
    int ht=h.dataWindow().max.y-h.dataWindow().min.y+1;
    bool gray=h.channels().findChannel("R")==nullptr;
    std::vector<float> pixels(w*ht*4,1.0f); FrameBuffer fb;
    for(int i=0;i<4;i++){
        const char* name=gray?"Y":(i==0?"R":i==1?"G":i==2?"B":"A");
        if(gray && i!=0) continue;
        if(!h.channels().findChannel(name))continue;
        char* base=(char*)(pixels.data()+i)-h.dataWindow().min.x*16-h.dataWindow().min.y*w*16;
        fb.insert(name,Slice(FLOAT,base,16,w*16));
    }
    f.setFrameBuffer(fb);f.readPixels(h.dataWindow().min.y,h.dataWindow().max.y);
    if(gray) for(int p=0;p<w*ht;p++)pixels[p*4+1]=pixels[p*4+2]=pixels[p*4];
    std::ofstream out(output,std::ios::binary);
    out.write((char*)pixels.data(),pixels.size()*4);
}
static void generate(const std::string& dir) {
    for(int codec=5;codec<=9;codec++)for(int shape=0;shape<9;shape++){
        int w=9,ht=(codec==9?257:35); bool gray=shape==2||shape==3;
        if(shape==2||shape==3){w=11;ht=17;}
        if(shape==4){w=16;ht=32;}
        if(shape==5){w=17;ht=17;}
        if(shape==6){w=1;ht=1;}
        if(shape==7){w=8;ht=8;}
        std::map<std::string,Plane> planes;
        PixelType base=shape==1||shape==3?FLOAT:HALF;
        for(auto name:gray?std::vector<std::string>{"A","Y"}:std::vector<std::string>{"A","B","G","R"})
            planes.emplace(name,Plane(base,shape==2||shape==5,w*ht));
        if(shape==7){
            planes["A"]=Plane(FLOAT,false,w*ht);planes["R"]=Plane(FLOAT,false,w*ht);
            planes.emplace("id",Plane(UINT,false,w*ht));
            planes.emplace("Z",Plane(FLOAT,false,w*ht));
            for(auto name:{"aux.B","aux.G","aux.R"})planes.emplace(name,Plane(HALF,false,w*ht));
        }
        int c=0;
        for(auto& p:planes){
            for(int y=0;y<ht;y++)for(int x=0;x<w;x++){
                float v=(float(x)*0.11f+float(y)*0.017f+float(c)*0.23f)-0.3f;
                if(p.first=="A")v=float(x%5)*0.125f+0.25f;
                if(shape==8)v=p.first=="A"?float((x+y)%7)/6.0f:float((x*7+y*3+c*11)%73)/31.0f-0.25f;
                if(shape==4||shape==6)v=p.first=="A"?0.75f:0.5f;
                if(shape==5)v=float(x+c+y)*0.15f;
                p.second.set(y*w+x,v);
            }c++;
        }
        Header header(w,ht);header.compression()=Compression(codec);FrameBuffer fb;
        for(auto& p:planes){
            header.channels().insert(p.first,Channel(p.second.type,1,1,p.second.linear));
            fb.insert(p.first,Slice(p.second.type,p.second.bytes.data(),p.second.stride(),w*p.second.stride()));
        }
        auto path=dir+"/c"+std::to_string(codec)+"_s"+std::to_string(shape)+".exr";
        { OutputFile f(path.c_str(),header);f.setFrameBuffer(fb);f.writePixels(ht); }
        decode(path,path+".rgba");
        std::vector<float> input(w*ht*4,1.0f);
        for(int p=0;p<w*ht;p++)for(int component=0;component<4;component++){
            if(gray && component==3)continue;
            std::string name=gray?"Y":component==0?"R":component==1?"G":component==2?"B":"A";
            const auto& plane=planes.at(name);
            if(plane.type==HALF){IMATH_NAMESPACE::half h;std::memcpy(&h,plane.bytes.data()+p*2,2);input[p*4+component]=float(h);}
            else std::memcpy(input.data()+p*4+component,plane.bytes.data()+p*4,4);
        }
        std::ofstream source(path+".input",std::ios::binary);source.write((char*)input.data(),input.size()*4);
        std::cout<<codec<<" "<<shape<<" "<<w<<" "<<ht<<"\n";
    }
}
int main(int argc,char** argv){
    static_assert(OPENEXR_VERSION_MAJOR==3 && OPENEXR_VERSION_MINOR==1 && OPENEXR_VERSION_PATCH==5,"Pin OpenEXR 3.1.5");
    try {
        if(argc==3 && std::string(argv[1])=="generate")generate(argv[2]);
        else if(argc==4 && std::string(argv[1])=="decode")decode(argv[2],argv[3]);
        else {std::cerr<<"reference generate DIR | reference decode FILE RGBA\n";return 2;}
    }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
