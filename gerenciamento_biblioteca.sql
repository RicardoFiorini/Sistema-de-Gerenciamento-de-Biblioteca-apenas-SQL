-- =================================================================
-- Script de Criação do Banco de Dados: Sistema de Biblioteca
-- Foco: Integridade de Dados, Performance e Robustez.
-- Dialeto: MySQL / MariaDB
-- =================================================================

-- Remove objetos antigos se existirem para tornar o script idempotente
DROP VIEW IF EXISTS ActiveLoans;
DROP VIEW IF EXISTS BooksWithAuthors;
DROP FUNCTION IF EXISTS CalculateLateDays;
DROP TRIGGER IF EXISTS trg_AfterLoanUpdate;
DROP TRIGGER IF EXISTS trg_AfterLoanInsert;
DROP TRIGGER IF EXISTS trg_BeforeLoanInsert;
DROP TABLE IF EXISTS Loans;
DROP TABLE IF EXISTS Members;
DROP TABLE IF EXISTS Books;
DROP TABLE IF EXISTS Authors;

-- =================================================================
-- 1. CRIAÇÃO DAS TABELAS
-- =================================================================

-- Tabela de Autores
CREATE TABLE Authors (
    AuthorID INT PRIMARY KEY AUTO_INCREMENT,
    Name VARCHAR(255) NOT NULL,
    BirthDate DATE,
    Nationality VARCHAR(100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de Livros
CREATE TABLE Books (
    BookID INT PRIMARY KEY AUTO_INCREMENT,
    Title VARCHAR(255) NOT NULL,
    AuthorID INT NOT NULL, -- Um livro deve ter um autor
    Genre VARCHAR(100),
    PublicationYear YEAR(4), -- Mais eficiente que INT para anos
    IsAvailable BOOLEAN DEFAULT TRUE NOT NULL,
    
    FOREIGN KEY (AuthorID) REFERENCES Authors(AuthorID)
        ON DELETE RESTRICT -- Impede excluir um autor que tenha livros
        ON UPDATE CASCADE,
        
    CHECK (PublicationYear IS NULL OR (PublicationYear > 1000 AND PublicationYear <= YEAR(CURRENT_DATE)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de Membros
CREATE TABLE Members (
    MemberID INT PRIMARY KEY AUTO_INCREMENT,
    Name VARCHAR(255) NOT NULL,
    Email VARCHAR(255) UNIQUE NOT NULL,
    Phone VARCHAR(20),
    JoinDate DATE DEFAULT CURRENT_DATE NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de Empréstimos
CREATE TABLE Loans (
    LoanID INT PRIMARY KEY AUTO_INCREMENT,
    BookID INT NOT NULL,
    MemberID INT NOT NULL,
    LoanDate DATE DEFAULT CURRENT_DATE NOT NULL,
    DueDate DATE NOT NULL, -- Um empréstimo deve ter data de devolução
    ReturnDate DATE, -- Permite NULL até ser devolvido
    
    FOREIGN KEY (BookID) REFERENCES Books(BookID)
        ON DELETE RESTRICT -- Impede excluir um livro com histórico de empréstimo
        ON UPDATE CASCADE,
        
    FOREIGN KEY (MemberID) REFERENCES Members(MemberID)
        ON DELETE RESTRICT -- Impede excluir um membro com histórico de empréstimo
        ON UPDATE CASCADE,
        
    CHECK (DueDate >= LoanDate),
    CHECK (ReturnDate IS NULL OR ReturnDate >= LoanDate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =================================================================
-- 2. CRIAÇÃO DE ÍNDICES PARA PERFORMANCE
-- =================================================================

-- Índices para Chaves Estrangeiras (melhora performance de JOINs)
CREATE INDEX idx_book_author ON Books(AuthorID);
CREATE INDEX idx_loan_book ON Loans(BookID);
CREATE INDEX idx_loan_member ON Loans(MemberID);

-- Índices para buscas comuns
CREATE INDEX idx_book_title ON Books(Title);
CREATE INDEX idx_member_name ON Members(Name);
CREATE INDEX idx_loan_returndate ON Loans(ReturnDate); -- Essencial para a view ActiveLoans

-- =================================================================
-- 3. CRIAÇÃO DE FUNÇÕES
-- =================================================================

-- Função para calcular dias de atraso
-- (Corrigido o bug de sombreamento de variável e melhorada a lógica)
DELIMITER $$
CREATE FUNCTION CalculateLateDays(p_LoanID INT) 
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_lateDays INT DEFAULT 0;
    DECLARE v_dueDate DATE;
    DECLARE v_returnDate DATE;

    -- Seleciona as datas relevantes para o empréstimo específico
    SELECT DueDate, ReturnDate 
    INTO v_dueDate, v_returnDate
    FROM Loans 
    WHERE LoanID = p_LoanID;

    -- Se o livro foi devolvido, calcula atraso baseado na data de devolução
    IF v_returnDate IS NOT NULL THEN
        SET v_lateDays = DATEDIFF(v_returnDate, v_dueDate);
    -- Se não foi devolvido, calcula atraso baseado na data ATUAL
    ELSE
        SET v_lateDays = DATEDIFF(CURRENT_DATE, v_dueDate);
    END IF;
    
    -- Retorna 0 se não houver atraso
    RETURN IF(v_lateDays < 0, 0, v_lateDays);
END$$
DELIMITER ;

-- =================================================================
-- 4. CRIAÇÃO DE TRIGGERS (Gatilhos)
-- =================================================================

DELIMITER $$

-- Gatilho para *ANTES* de inserir um empréstimo
-- Impede o empréstimo de um livro que não está disponível
CREATE TRIGGER trg_BeforeLoanInsert
BEFORE INSERT ON Loans
FOR EACH ROW
BEGIN
    DECLARE v_isAvailable BOOLEAN;

    SELECT IsAvailable 
    INTO v_isAvailable 
    FROM Books 
    WHERE BookID = NEW.BookID;

    IF v_isAvailable = FALSE THEN
        SIGNAL SQLSTATE '45000' -- "Unmapped user-defined exception"
        SET MESSAGE_TEXT = 'Não é possível emprestar o livro: já está indisponível.';
    END IF;
END$$

-- Gatilho para *DEPOIS* de inserir um empréstimo
-- Atualiza a disponibilidade do livro para FALSE
CREATE TRIGGER trg_AfterLoanInsert
AFTER INSERT ON Loans
FOR EACH ROW
BEGIN
    UPDATE Books
    SET IsAvailable = FALSE
    WHERE BookID = NEW.BookID;
END$$

-- Gatilho para *DEPOIS* de atualizar um empréstimo
-- Atualiza a disponibilidade do livro quando é devolvido (ou a devolução é desfeita)
CREATE TRIGGER trg_AfterLoanUpdate
AFTER UPDATE ON Loans
FOR EACH ROW
BEGIN
    -- Caso 1: O livro está sendo devolvido (ReturnDate de NULL para uma data)
    IF NEW.ReturnDate IS NOT NULL AND OLD.ReturnDate IS NULL THEN
        UPDATE Books
        SET IsAvailable = TRUE
        WHERE BookID = NEW.BookID;
        
    -- Caso 2: A devolução foi "desfeita" (ReturnDate de uma data para NULL)
    ELSEIF NEW.ReturnDate IS NULL AND OLD.ReturnDate IS NOT NULL THEN
        UPDATE Books
        SET IsAvailable = FALSE
        WHERE BookID = NEW.BookID;
    END IF;
END$$

DELIMITER ;

-- =================================================================
-- 5. CRIAÇÃO DE VIEWS (Visões)
-- =================================================================

-- View para visualizar todos os empréstimos ativos (não devolvidos)
CREATE VIEW ActiveLoans AS
SELECT 
    l.LoanID,
    b.Title,
    m.Name AS MemberName,
    m.Email AS MemberEmail,
    l.LoanDate,
    l.DueDate
FROM 
    Loans l
JOIN 
    Books b ON l.BookID = b.BookID
JOIN 
    Members m ON l.MemberID = m.MemberID
WHERE 
    l.ReturnDate IS NULL; -- O índice idx_loan_returndate otimiza isso

-- View para visualizar todos os livros com informações do autor
CREATE VIEW BooksWithAuthors AS
SELECT 
    b.BookID,
    b.Title,
    a.Name AS AuthorName,
    a.Nationality AS AuthorNationality,
    b.Genre,
    b.PublicationYear,
    b.IsAvailable
FROM 
    Books b
JOIN 
    Authors a ON b.AuthorID = a.AuthorID;

-- =================================================================
-- 6. DADOS DE EXEMPLO (POPULATE)
-- =================================================================

-- Inserindo autores
INSERT INTO Authors (Name, BirthDate, Nationality) VALUES 
('George Orwell', '1903-06-25', 'British'),
('Harper Lee', '1926-04-28', 'American'),
('J.R.R. Tolkien', '1892-01-03', 'British');

-- Inserindo livros
INSERT INTO Books (Title, AuthorID, Genre, PublicationYear) VALUES 
('1984', 1, 'Dystopian', 1949),
('To Kill a Mockingbird', 2, 'Fiction', 1960),
('Animal Farm', 1, 'Allegory', 1945),
('The Lord of the Rings', 3, 'Fantasy', 1954);

-- Inserindo membros
INSERT INTO Members (Name, Email, Phone) VALUES 
('John Doe', 'john@example.com', '1234567890'),
('Jane Smith', 'jane@example.com', '0987654321');

-- Registrando um empréstimo (Livro '1984' para 'John Doe')
-- O trigger trg_AfterLoanInsert marcará '1984' como IsAvailable = FALSE
INSERT INTO Loans (BookID, MemberID, DueDate) VALUES 
(1, 1, DATE_ADD(CURRENT_DATE, INTERVAL 14 DAY));

-- Registrando outro empréstimo (Livro 'To Kill a Mockingbird' para 'Jane Smith')
INSERT INTO Loans (BookID, MemberID, DueDate) VALUES 
(2, 2, DATE_ADD(CURRENT_DATE, INTERVAL 10 DAY));

-- Tentativa de emprestar um livro já emprestado (DEVE FALHAR)
-- Descomente a linha abaixo para testar o trigger trg_BeforeLoanInsert
-- INSERT INTO Loans (BookID, MemberID, DueDate) VALUES (1, 2, DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY));

-- Atualizando a devolução de um livro (John Doe devolve '1984')
-- O trigger trg_AfterLoanUpdate marcará '1984' como IsAvailable = TRUE
UPDATE Loans SET ReturnDate = CURRENT_DATE WHERE LoanID = 1;

-- =================================================================
-- 7. EXEMPLOS DE CONSULTAS
-- =================================================================

-- Consultando livros com autores (usando a View)
SELECT * FROM BooksWithAuthors;

-- Consultando empréstimos ativos (usando a View)
-- (Deve mostrar apenas o empréstimo de 'Jane Smith', já que 'John Doe' devolveu o dele)
SELECT * FROM ActiveLoans;

-- Consultando todos os livros e sua disponibilidade
SELECT Title, IsAvailable FROM Books;

-- Usando a função para calcular dias de atraso (para todos os empréstimos)
SELECT 
    LoanID,
    (SELECT Title FROM Books b WHERE b.BookID = l.BookID) AS BookTitle,
    DueDate,
    ReturnDate,
    CalculateLateDays(LoanID) AS DaysLate
FROM Loans l;

-- =================================================================
-- FIM DO SCRIPT
-- =================================================================
