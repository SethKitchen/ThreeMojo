"""Bind local ordered/nonnegative-error selection producers and exact constants."""
from pathlib import Path
if __package__:
    from . import source_contracts
else:
    import source_contracts
EXPECTED={
'extensions/carla/spiral_grouped_roundoff_proof.mojo':'a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7',
'extensions/carla/spiral_roundoff_proof.mojo':'634c4f0f448b472301a42ad6065655f60cf78121f12bafa64085a1e67108fc0f'}
INTERVAL='e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11'

def _scalar(text,name):
    # Lazy imports avoid a cycle with maintained migration verifiers.
    if __package__:
        from . import spiral_moments as moments
        from . import ideal_projection
    else:
        import spiral_moments as moments
        import ideal_projection
    statements=ideal_projection.module_statements(text)
    matches=[s for s in statements if s[:2]==[('NAME','comptime'),('NAME',name)]]
    if len(matches)!=1:raise ValueError('Missing or ambiguous selector constant')
    s=matches[0];prefix=[('NAME','comptime'),('NAME',name),('OP','='),('NAME','Float64'),('OP','(')]
    if s[:len(prefix)]!=prefix or s[-1]!=('OP',')'):raise ValueError('Unsupported complete selector constant declaration')
    literal=moments.literal_from_tokens(s[len(prefix):-1],'selector constant '+name)
    return moments.fraction_of_word(moments.decimal_word(literal))

def verify_text(modules,interval,trig):
    if set(modules)!=set(EXPECTED):raise ValueError('Wrong selection producer set')
    for p,text in modules.items():
        if source_contracts.token_sha256(text)!=EXPECTED[p]:raise ValueError('Selection producer/input/error/phase graph changed: '+p)
    if source_contracts.token_sha256(interval)!=INTERVAL:raise ValueError('Ordering or nonnegative-error arithmetic changed')
    k=_scalar(trig,'_INV_HALF_PI');limit=_scalar(trig,'_PHASE_LIMIT')
    if not 0<k<=1:raise ValueError('Selector multiplier bound')
    if not 0<limit<=1048576:raise ValueError('Finite phase bound')
    return {'status':'PASS','ordered_theta':True,'nonnegative_error':True,'selector_endpoint_magnitude_below':4194304}

def _producer_text(root, path):
    """Admit only the exact current Y successor before a selection view."""
    text = (root/path).read_text()
    if (path == 'extensions/carla/spiral_grouped_roundoff_proof.mojo'
            and source_contracts.token_sha256(text) != EXPECTED[path]):
        if __package__:
            from . import grouped_y_finiteness_contracts as grouped_y
        else:
            import grouped_y_finiteness_contracts as grouped_y
        text = grouped_y.predecessor_text(root, path)
    return text


def verify(root):
    root=Path(root)
    return verify_text({p:_producer_text(root,p) for p in EXPECTED},(root/'extensions/carla/curve_interval.mojo').read_text(),(root/'extensions/carla/curve_trig.mojo').read_text())


def predecessor_text(root, path):
    """Verify both actual producers before reconstructing one legacy module."""
    import hashlib
    import json
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    root=Path(root)
    verify(root)
    payload=(root/'tools/carla_lane_oracle/selection-finiteness-contract.json').read_bytes()
    if hashlib.sha256(payload).hexdigest()!='dcd2c780640775e29a566491679dc6fbf5ab1afa43fbfbae86cb778433cf92e8':
        raise ValueError('Unreviewed selection predecessor record')
    record=json.loads(payload,object_pairs_hook=source_contracts.unique_keys)
    if path not in EXPECTED or set(record['modules'])!=set(EXPECTED):
        raise ValueError('Wrong selection predecessor module')
    item=record['modules'][path]
    name=('_try_spiral_grouped_roundoff_envelope' if path.endswith('/spiral_grouped_roundoff_proof.mojo')
          else '_try_spiral_roundoff_envelope')
    text=_producer_text(root,path)
    body,span,tokens=guard.function_span(text,name,())
    if guard.significant(body)!=guard.significant(item['after_complete_function']):
        raise ValueError('Selection complete successor body changed')
    first=tokens[span[0]].start[0]-1;last=tokens[span[1]-1].start[0]-1
    lines=text.splitlines(keepends=True)
    restored=''.join(lines[:first])+item['before_complete_function']+''.join(lines[last:])
    if source_contracts.token_sha256(restored)!=item['before_token_sha256']:
        raise ValueError('Selection predecessor reconstruction failed')
    return restored
