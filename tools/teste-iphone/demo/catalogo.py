import re, json, glob
prof = {}; esp = {}
rp = re.compile(r"\('([a-z0-9-]+)', '([^']+)', '([a-z_]+)', '(#[0-9a-f]{6})', '(#[0-9a-f]{6})', (\d+), (true|false), array\[([^\]]*)\]::text\[\], (\d+)\)")
re_ = re.compile(r"\('([a-z0-9-]+)', '([^']+)', (\d+)\)")
for f in sorted(glob.glob('supabase/migrations/*.sql')):
    s = re.sub(r',\s*\n\s*', ', ', open(f).read())
    for m in rp.finditer(s):
        prof[m[1]] = dict(id=m[1], nome=m[2], icone=m[3], cor_inicio=m[4], cor_fim=m[5], exige_antecedentes=m[7]=='true',
                          palavras_chave=re.findall(r"'([^']*)'", m[8]), ordem=int(m[9]))
    for blk in re.findall(r"insert into public\.especialidades \(profissao_id, nome, ordem\) values(.*?);", s, re.S):
        for m in re_.finditer(blk):
            esp.setdefault(m[1], {})[m[2]] = int(m[3])
out = []; i = 1
for p in sorted(prof.values(), key=lambda p: p['ordem']):
    es = []
    for nome, o in sorted(esp.get(p['id'], {}).items(), key=lambda x: x[1]):
        es.append(dict(id=i, nome=nome)); i += 1
    p['especialidades'] = es; out.append(p)
print(len(out), [p['id'] for p in out])
open('packages/iservice_core/lib/demo_catalogo.dart','w').write("// Gerado para as capturas de demonstração.\nconst catalogoDemoJson = r'''" + json.dumps(out, ensure_ascii=False) + "''';\n")
