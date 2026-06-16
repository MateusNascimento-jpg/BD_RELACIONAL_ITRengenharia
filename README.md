# ITR Engenharia — Banco de Dados para Gestão de Amostras

Camada de persistência e modelagem relacional em MySQL desenvolvida para o **Sistema de Gestão de Amostras Laboratoriais** da ITR Engenharia. Este repositório concentra a inteligência de dados, tabelas estruturadas e restrições de integridade que servem de fundação para a futura API (Node.js/Express) e integração com o Airtable.

## Características da Engenharia do Banco

* **Arquitetura Relacional Conectada:** Modelagem focada no ecossistema laboratorial, estabelecendo relacionamentos precisos (Chaves Estrangeiras) entre as tabelas de **Amostras**, **Clientes** e **Ensaios Técnicos** para impedir a redundância.
* **Consistência para Dados Dinâmicos:** Tabelas projetadas estrategicamente para validar e armazenar os campos de seleção dinâmicos provenientes da API do Airtable, garantindo integridade quando o back-end sincronizar os dados.
* **Performance em Consultas (Busca em Tempo Real):** Implementação de índices estruturados (B-Tree) nas colunas de maior relevância de pesquisa, permitindo que a busca em tempo real da interface web responda em microsegundos, sem gargalos.
* **Validação Nativa no Motor do Banco:** Uso de restrições de validação rígidas (`Constraints`) que blindam o banco de dados contra payloads malformados antes mesmo que a informação chegue à camada de aplicação.

## Tecnologias Utilizadas
* **SGBD:** MySQL 8.0+
* **Modelagem:** Relacional (SQL ANSI)
* **Mecanismo de Armazenamento:** MySQL Workbench (Suporte total a transações ACID)

---
© **ITR Engenharia** — *Uso interno e restrito.*

