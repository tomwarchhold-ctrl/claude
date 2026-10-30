#!/usr/bin/env python3
"""Rechnung aus vorlage.docx erzeugen.
Aufruf: python3 rechnung/erstellen.py daten.json   (oder JSON auf stdin)
JSON: {"nr":"2026041","datum":"07.10.2026",
       "empfaenger":["Firma","Strasse","PLZ Ort"],
       "objekt":["Strasse","Ort"],
       "positionen":[{"anzahl":24,"einheit":"Std.","text":"Trockenbauarbeiten","preis":45.0}],
       "mwst":19 (oder "mwst_betrag":55.5 fuer festen MwSt-Betrag), "zahlungsziel_tage":14 (optional, Standard 7),
       "out":"Rechnung_2026041_Firma.docx"}
Positionen sind Netto; Summe/MwSt/Brutto werden berechnet."""
import json,re,sys,zipfile,os
here=os.path.dirname(os.path.abspath(__file__))
cfg=json.load(open(sys.argv[1]) if len(sys.argv)>1 else sys.stdin)
eur=lambda v:('{:,.2f}'.format(v).replace(',','X').replace('.',',').replace('X','.'))+' €'
num=lambda v:('%g'%v).replace('.',',')
z=zipfile.ZipFile(os.path.join(here,'vorlage.docx'))
d=z.read('word/document.xml').decode('utf8')
def lines(ls):
    return ''.join(('<w:r><w:br/></w:r>' if i else '')+'<w:r><w:t xml:space="preserve">%s</w:t></w:r>'%l for i,l in enumerate(ls))
def setpara(pid,ls):
    global d
    m=re.search(r'(<w:p w14:paraId="%s"[^>]*>).*?(</w:p>)'%pid,d,re.S)
    d=d[:m.end(1)]+lines(ls)+d[m.start(2):]
setpara('29318531',cfg['empfaenger'])
setpara('7C391F9B',cfg['objekt'])
d=d.replace('Datum: 05.10.2026','Datum: '+cfg['datum']).replace('-Nr.: 2026039','-Nr.: '+cfg['nr'])
d=d.replace(': 7 Tage',': %d Tage'%cfg.get('zahlungsziel_tage',7),1)
ts=d.index('<w:tbl>',d.index('7C391F9B')); te=d.index('</w:tbl>',ts)
tbl=d[ts:te]
rows=re.findall(r'<w:tr [^>]*>.*?</w:tr>',tbl,re.S)
hdr,_,shaded,plain,summe,ges=rows
def settexts(row,vals):
    cells=re.findall(r'<w:tc>.*?</w:tc>',row,re.S); out=row
    for c,v in zip(cells,vals):
        m=re.search(r'(<w:p [^>]*?)(/>|>.*?</w:p>)',c,re.S)
        run='<w:r><w:t xml:space="preserve">%s</w:t></w:r>'%v if v else ''
        out=out.replace(c,c[:m.start()]+m.group(1)+'>'+run+'</w:p>'+c[m.end():],1)
    return re.sub(r'w14:paraId="[0-9A-F]+"','',out)
body='';netto=0
for i,p in enumerate(cfg['positionen']):
    g=round(p['anzahl']*p['preis'],2);netto+=g
    body+=settexts(shaded if i%2==0 else plain,[str(i+1),num(p['anzahl']),p['einheit'],p['text'],eur(p['preis']),eur(g)])
mw=cfg['mwst_betrag'] if 'mwst_betrag' in cfg else round(netto*cfg.get('mwst',19)/100,2)
body+=settexts(summe,['','','','Summe (netto)','',eur(netto)])
body+=settexts(summe,['','','','zzgl. %g %% MwSt.'%cfg.get('mwst',19),'',eur(mw)])
body+=settexts(ges,['','','','Gesamtbetrag (brutto):','',eur(netto+mw)])
d=d[:ts]+tbl[:tbl.index(rows[0])]+hdr+body+d[te:]
out=cfg.get('out','Rechnung_%s.docx'%cfg['nr'])
zo=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)
for it in z.infolist():
    zo.writestr(it,d.encode('utf8') if it.filename=='word/document.xml' else z.read(it.filename))
zo.close();print(out,eur(netto),eur(mw),eur(netto+mw))
