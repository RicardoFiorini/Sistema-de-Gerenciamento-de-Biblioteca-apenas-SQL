-- =================================================================
-- PROJETO: Sistema de Gestão de Biblioteca (High Performance)
-- AUTOR: Ricardo Fiorini Cuato
-- DATA: 2025
-- DIALETO: MySQL 8.0 / MariaDB 10.5+
-- =================================================================

SET NAMES utf8mb4;
SET TIME_ZONE = '-03:00';
SET FOREIGN_KEY_CHECKS = 0;

-- =================================================================
-- 1. LIMPEZA DE AMBIENTE (Idempotência)
-- =================================================================
DROP VIEW IF EXISTS vw_ActiveLoans;
DROP VIEW IF EXISTS vw_BookDetails;
DROP PROCEDURE IF EXISTS sp_RegisterLoan;
DROP PROCEDURE IF EXISTS sp_ProcessReturn;
DROP TRIGGER IF EXISTS trg_Books_UpdateTimestamp;
DROP TRIGGER IF EXISTS trg_Members_UpdateTimestamp;
DROP TABLE IF EXISTS Loans;
DROP TABLE IF EXISTS Books;
DROP TABLE IF EXISTS Members;
DROP TABLE IF EXISTS Authors;

-- =================================================================
-- 2. ESTRUTURA DE TABELAS
-- =================================================================

-- Tabela: Autores
CREATE TABLE Authors (
    AuthorID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    BirthDate DATE,
    Nationality VARCHAR(100),
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_author_name (Name) -- Índice para busca rápida por nome
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: Membros
CREATE TABLE Members (
    MemberID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Email VARCHAR(255) NOT NULL,
    Phone VARCHAR(20),
    Status ENUM('Active', 'Suspended', 'Inactive') DEFAULT 'Active',
    JoinDate DATE DEFAULT (CURRENT_DATE),
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT uq_member_email UNIQUE (Email),
    INDEX idx_member_status (Status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: Livros
CREATE TABLE Books (
    BookID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    Title VARCHAR(255) NOT NULL,
    AuthorID INT UNSIGNED NOT NULL,
    Genre VARCHAR(100),
    PublicationYear YEAR,
    IsAvailable BOOLEAN DEFAULT TRUE NOT NULL,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_book_author FOREIGN KEY (AuthorID) 
        REFERENCES Authors(AuthorID) ON DELETE RESTRICT ON UPDATE CASCADE,
    
    -- Constraint de integridade lógica
    CONSTRAINT chk_pub_year CHECK (PublicationYear <= YEAR(CURRENT_DATE)),

    -- Índices
    INDEX idx_book_genre (Genre),
    FULLTEXT idx_book_title_ft (Title) -- Performance superior para buscas textuais (ex: "Harry Potter")
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: Empréstimos
CREATE TABLE Loans (
    LoanID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    BookID INT UNSIGNED NOT NULL,
    MemberID INT UNSIGNED NOT NULL,
    LoanDate DATE DEFAULT (CURRENT_DATE) NOT NULL,
    DueDate DATE NOT NULL,
    ReturnDate DATE NULL,
    
    -- Coluna Gerada (Virtual): Calcula dias de atraso nativamente sem custo de função escalar
    DaysOverdue INT GENERATED ALWAYS AS (
        CASE 
            WHEN ReturnDate IS NULL AND CURRENT_DATE > DueDate THEN DATEDIFF(CURRENT_DATE, DueDate)
            WHEN ReturnDate IS NOT NULL AND ReturnDate > DueDate THEN DATEDIFF(ReturnDate, DueDate)
            ELSE 0 
        END
    ) VIRTUAL,

    Status ENUM('Active', 'Returned', 'Overdue') DEFAULT 'Active',
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_loan_book FOREIGN KEY (BookID) 
        REFERENCES Books(BookID) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_loan_member FOREIGN KEY (MemberID) 
        REFERENCES Members(MemberID) ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT chk_loan_dates CHECK (DueDate >= LoanDate),
    CONSTRAINT chk_return_date CHECK (ReturnDate IS NULL OR ReturnDate >= LoanDate),

    -- Índices compostos para performance de dashboard
    INDEX idx_loan_status_dates (Status, DueDate),
    INDEX idx_loan_member_history (MemberID, LoanDate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =================================================================
-- 3. STORED PROCEDURES (Lógica de Negócio ACID)
-- =================================================================

DELIMITER $$

-- Procedure: Registrar Empréstimo de forma segura
CREATE PROCEDURE sp_RegisterLoan(
    IN p_BookID INT UNSIGNED,
    IN p_MemberID INT UNSIGNED,
    IN p_Days INT
)
BEGIN
    DECLARE v_IsAvailable BOOLEAN;
    DECLARE v_MemberStatus VARCHAR(20);

    -- Inicia Transação
    START TRANSACTION;

    -- Verifica disponibilidade e trava a linha para leitura (FOR UPDATE)
    SELECT IsAvailable INTO v_IsAvailable 
    FROM Books WHERE BookID = p_BookID FOR UPDATE;

    -- Verifica status do membro
    SELECT Status INTO v_MemberStatus 
    FROM Members WHERE MemberID = p_MemberID;

    IF v_IsAvailable = FALSE THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Erro: Livro indisponível.';
    ELSEIF v_MemberStatus != 'Active' THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Erro: Membro não está ativo.';
    ELSE
        -- Insere Empréstimo
        INSERT INTO Loans (BookID, MemberID, LoanDate, DueDate, Status)
        VALUES (p_BookID, p_MemberID, CURRENT_DATE, DATE_ADD(CURRENT_DATE, INTERVAL p_Days DAY), 'Active');

        -- Atualiza Livro
        UPDATE Books SET IsAvailable = FALSE WHERE BookID = p_BookID;

        COMMIT;
    END IF;
END$$

-- Procedure: Realizar Devolução
CREATE PROCEDURE sp_ProcessReturn(
    IN p_LoanID INT UNSIGNED
)
BEGIN
    DECLARE v_BookID INT UNSIGNED;
    DECLARE v_DueDate DATE;
    
    START TRANSACTION;

    -- Pega dados do empréstimo
    SELECT BookID, DueDate INTO v_BookID, v_DueDate 
    FROM Loans WHERE LoanID = p_LoanID FOR UPDATE;

    IF v_BookID IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Erro: Empréstimo não encontrado.';
    ELSE
        -- Atualiza Empréstimo
        UPDATE Loans 
        SET ReturnDate = CURRENT_DATE,
            Status = IF(CURRENT_DATE > v_DueDate, 'Overdue', 'Returned')
        WHERE LoanID = p_LoanID;

        -- Libera Livro
        UPDATE Books SET IsAvailable = TRUE WHERE BookID = v_BookID;

        COMMIT;
    END IF;
END$$

DELIMITER ;

-- =================================================================
-- 4. VIEWS OTIMIZADAS
-- =================================================================

-- Relatório de Empréstimos Ativos e Atrasados
CREATE VIEW vw_ActiveLoans AS
SELECT 
    l.LoanID,
    b.Title AS BookTitle,
    m.Name AS MemberName,
    m.Email,
    l.LoanDate,
    l.DueDate,
    l.DaysOverdue, -- Usa a coluna calculada nativa
    CASE 
        WHEN l.DaysOverdue > 0 THEN 'ATRASADO'
        ELSE 'NO PRAZO'
    END AS Situation
FROM Loans l
JOIN Books b ON l.BookID = b.BookID
JOIN Members m ON l.MemberID = m.MemberID
WHERE l.ReturnDate IS NULL;

-- Detalhes Completos dos Livros
CREATE VIEW vw_BookDetails AS
SELECT 
    b.BookID,
    b.Title,
    a.Name AS Author,
    b.Genre,
    b.PublicationYear,
    CASE WHEN b.IsAvailable THEN 'Disponível' ELSE 'Emprestado' END AS Status
FROM Books b
INNER JOIN Authors a ON b.AuthorID = a.AuthorID;

-- =================================================================
-- 5. POPULATE INICIAL (Dados de Teste)
-- =================================================================
SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO Authors (Name, Nationality) VALUES 
('George Orwell', 'British'), 
('J.K. Rowling', 'British'),
('Isaac Asimov', 'American');

INSERT INTO Members (Name, Email, Phone) VALUES 
('Ricardo Fiorini', 'ricardo@usf.edu.br', '19999999999'),
('Aluno Exemplo', 'aluno@teste.com', '11988888888');

INSERT INTO Books (Title, AuthorID, Genre, PublicationYear) VALUES 
('1984', 1, 'Dystopian', 1949),
('Harry Potter e a Pedra Filosofal', 2, 'Fantasy', 1997),
('Foundation', 3, 'Sci-Fi', 1951);

-- Testando a Procedure de Empréstimo
CALL sp_RegisterLoan(1, 1, 14); -- Ricardo pega 1984
CALL sp_RegisterLoan(2, 2, 7);  -- Aluno pega Harry Potter

-- =================================================================
-- FIM DO SCRIPT
-- =================================================================
