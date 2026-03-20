# Sistema de Biblioteca (Apenas SQL)
Um projeto focado em **modelagem de banco de dados relacional** para gerenciar o fluxo de uma biblioteca, sem a necessidade de uma linguagem de programação externa.
## Estrutura do Projeto
O sistema foi projetado para cobrir todas as necessidades básicas de organização de dados, incluindo:

- **Normalização:** Divisão eficiente entre autores, livros e categorias.
- **Integridade:** Uso de *Foreign Keys* para evitar empréstimos de livros inexistentes.
- **Consultas Avançadas:** Scripts prontos para gerar relatórios de livros mais lidos e usuários com pendências.

## Status do Desenvolvimento
- [x] Criação das Tabelas (DDL)
- [x] Inserção de Dados de Exemplo (DML)
- [x] Consultas de Relatórios (SELECT/JOIN)
- [ ] Implementar Triggers para automação de estoque
## Exemplo de Consulta SQL
Abaixo, um exemplo de como o sistema busca livros emprestados vinculando as tabelas:
```sql

SELECT Usuarios.Nome, Livros.Titulo, Emprestimos.Data_Devolucao
FROM Emprestimos
JOIN Usuarios ON Emprestimos.ID_Usuario = Usuarios.ID
JOIN Livros ON Emprestimos.ID_Livro = Livros.ID
WHERE Emprestimos.Status = 'Ativo';

```
## Dicas de Uso
> [!TIP]
> Para testar este projeto, você pode utilizar qualquer SGDB compatível com SQL padrão, como MySQL, PostgreSQL ou SQL Server. Basta executar o script de criação seguido pelos inserts.
## Principais Tabelas
| Tabela | Responsabilidade |
| --- | --- |
| Livros | Armazena títulos, ISBN e quantidade disponível |
| Autores | Dados biográficos dos escritores |
| Emprestimos | Registra datas, prazos e status de devolução |
| Usuarios | Controle de contato e histórico dos leitores |
