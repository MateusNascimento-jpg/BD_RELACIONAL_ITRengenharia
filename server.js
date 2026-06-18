const express = require('express');
const pool = require('./db'); // Puxa a conexão do MySQL
require('dotenv').config();

const app = express();

// Permite que o servidor entenda dados em formato JSON (enviados pelas telas)
app.use(express.json());

// Uma rota de teste simples para verificar se o servidor está respondendo
app.get('/status', (req, res) => {
    // Teste rápido acessando no navegador: http://localhost:3000/status
    res.json({ status: "Online", projeto: "ITR Engenharia Login" });
});

// ==================== NOVA ROTA: CADASTRO ====================
app.post('/cadastro', async (req, res) => {
    const { documento, tipo_documento, email, senha, nome_empresa, perfil, airtable_client_id, operador } = req.body;

    try {
        // Executa a procedure no MySQL
        const sql = 'CALL procedure_cadastrar_usuario_cnpj(?, ?, ?, ?, ?, ?, ?, ?)';
        await pool.query(sql, [documento, tipo_documento, email, senha, nome_empresa, perfil, airtable_client_id, operador]);
        
        return res.status(201).json({ sucesso: true, mensagem: "Usuário cadastrado com sucesso pelo Node!" });
    } catch (error) {
        // Se o banco rejeitar (CPF inválido, e-mail duplicado, etc)    
        return res.status(400).json({ sucesso: false, erro: error.message });
    }
});     

// Define a porta do servidor (3000 por padrão)
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Servidor backend da ITR rodando na porta ${PORT}`);
});