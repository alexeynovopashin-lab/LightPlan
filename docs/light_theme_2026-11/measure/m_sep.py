import os,re,collections,sys
UI='Packages/LightPlanUI/Sources/LightPlanUI'
def area(p):
    p=p.replace(UI+'/','')
    if p.startswith('Screens/'): return p.split('/')[1]
    if p.startswith('LightPlanWidget'): return 'Widget'
    return p.split('/')[0].replace('.swift','')
pats={'стекло системное (.glassEffect)':r'\.glassEffect\(','материал iOS (Material)':r'\b(ultraThin|thin|regular|thick|ultraThick|bar)Material\b',
 'вуаль под стекло (sheetGlass/mapGlass/bar/fill)':r'\.(sheetGlass|mapGlass|bar2?|fillA|fillB)\b','блик (glassShine/drumLip/knobGlass)':r'\.(glassShine|drumLip|drumGlass|knobGlass)\b',
 'кант (strokeBorder/stroke)':r'\.(strokeBorder|stroke)\(','  из них чернилами (hairline/edge/ink…/hair…)':r'\.(strokeBorder|stroke)\([^)\n]*\b(hairline|edge|bezel|ink\d*b?|hair\d?|inkA\d+|rail\d?)\b',
 '  из них белым':r'\.(strokeBorder|stroke)\([^)\n]*(\.white|0xFFFFFF|glassShine)','тень (.shadow)':r'\.shadow\('}
cnt=collections.defaultdict(collections.Counter)
for s in [UI,'LightPlanWidget']:
    for dp,dn,fn in os.walk(s):
        for f in fn:
            if not f.endswith('.swift'): continue
            p=os.path.join(dp,f); t=open(p,encoding='utf-8').read()
            for k,r in pats.items(): cnt[area(p)][k]+=len(re.findall(r,t))
areas=sorted(cnt,key=lambda a:-sum(cnt[a].values()))
print('| место | '+' | '.join(pats)+' |'); print('|---'*(len(pats)+1)+'|')
for a in areas:
    if sum(cnt[a].values())==0: continue
    print(f'| {a} | '+' | '.join(str(cnt[a][k]) for k in pats)+' |')
tot=collections.Counter()
for a in cnt: tot.update(cnt[a])
print('| всего | '+' | '.join(str(tot[k]) for k in pats)+' |')
