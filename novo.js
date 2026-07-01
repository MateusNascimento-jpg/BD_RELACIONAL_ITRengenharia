// checar_clientes.js
require('dotenv').config();
const TOKEN = process.env.AIRTABLE_TOKEN;
const BASE = process.env.AIRTABLE_BASE_ID;
const TBL = 'tblkQxQ6q7cBKXZ3C'; // Clientes

async function rodar() {
  const url = `https://api.airtable.com/v0/${BASE}/${TBL}?maxRecords=4`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}` } });
  const dados = await resp.json();
  (dados.records || []).forEach((r, i) => {
    console.log(`\n=== registro ${i} (${r.id}) ===`);
    console.log('  Nome Cliente:', JSON.stringify(r.fields['Nome Cliente']));
    console.log('  ID Cliente  :', JSON.stringify(r.fields['ID Cliente']));
    console.log('  TODOS os campos:', Object.keys(r.fields).join(' | '));
  });
}
rodar();