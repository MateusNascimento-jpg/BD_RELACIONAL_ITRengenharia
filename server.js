const express = require('express');
const pool = require('./db'); // Puxa a conexão do MySQL que você configurou
require('dotenv').config();

const app = express();

// Permite que o servidor entenda dados em formato JSON (enviados pelas telas)
app.use(express.json());

// Uma rota de teste simples para verificar se o servidor está respondendo
app.get('/status', (req, res) => {
    res.json({ status: "Online", projeto: "ITR Engenharia Login" });
});

// Define a porta do servidor (3000 por padrão)
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Servidor backend da ITR rodando na porta ${PORT}`);
}); 