-- Tabela de Autores
CREATE TABLE Authors (
    AuthorID INT PRIMARY KEY AUTO_INCREMENT,
    Name VARCHAR(255) NOT NULL,
    BirthDate DATE,
    Nationality VARCHAR(100)
);

-- Tabela de Livros
CREATE TABLE Books (
    BookID INT PRIMARY KEY AUTO_INCREMENT,
    Title VARCHAR(255) NOT NULL,
    AuthorID INT,
    Genre VARCHAR(100),
    PublicationYear INT,
    IsAvailable BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (AuthorID) REFERENCES Authors(AuthorID)
);

-- Tabela de Membros
CREATE TABLE Members (
    MemberID INT PRIMARY KEY AUTO_INCREMENT,
    Name VARCHAR(255) NOT NULL,
    Email VARCHAR(255) UNIQUE NOT NULL,
    Phone VARCHAR(20),
    JoinDate DATE DEFAULT CURRENT_DATE
);

-- Tabela de Empréstimos
CREATE TABLE Loans (
    LoanID INT PRIMARY KEY AUTO_INCREMENT,
    BookID INT,
    MemberID INT,
    LoanDate DATE DEFAULT CURRENT_DATE,
    DueDate DATE,
    ReturnDate DATE,
    FOREIGN KEY (BookID) REFERENCES Books(BookID),
    FOREIGN KEY (MemberID) REFERENCES Members(MemberID)
);

-- Índice para melhorar a busca de livros por título
CREATE INDEX idx_book_title ON Books(Title);

-- Índice para melhorar a busca de membros por nome
CREATE INDEX idx_member_name ON Members(Name);

-- Função para calcular o atraso na devolução do livro
CREATE FUNCTION CalculateLateDays(LoanID INT) RETURNS INT
BEGIN
    DECLARE lateDays INT;
    DECLARE dueDate DATE;

    SELECT DueDate INTO dueDate FROM Loans WHERE LoanID = LoanID;
    
    SET lateDays = DATEDIFF(CURRENT_DATE, dueDate);
    
    RETURN IF(lateDays < 0, 0, lateDays);
END;

-- Trigger para atualizar a disponibilidade do livro ao registrar um empréstimo
CREATE TRIGGER trg_AfterLoanInsert
AFTER INSERT ON Loans
FOR EACH ROW
BEGIN
    UPDATE Books 
    SET IsAvailable = FALSE 
    WHERE BookID = NEW.BookID;
END;

-- Trigger para atualizar a disponibilidade do livro ao registrar uma devolução
CREATE TRIGGER trg_AfterLoanUpdate
AFTER UPDATE ON Loans
FOR EACH ROW
BEGIN
    IF NEW.ReturnDate IS NOT NULL THEN
        UPDATE Books 
        SET IsAvailable = TRUE 
        WHERE BookID = NEW.BookID;
    END IF;
END;

-- View para visualizar todos os empréstimos ativos
CREATE VIEW ActiveLoans AS
SELECT 
    l.LoanID,
    b.Title,
    m.Name AS MemberName,
    l.LoanDate,
    l.DueDate,
    l.ReturnDate
FROM 
    Loans l
JOIN 
    Books b ON l.BookID = b.BookID
JOIN 
    Members m ON l.MemberID = m.MemberID
WHERE 
    l.ReturnDate IS NULL;

-- View para visualizar todos os livros com informações do autor
CREATE VIEW BooksWithAuthors AS
SELECT 
    b.BookID,
    b.Title,
    a.Name AS AuthorName,
    b.Genre,
    b.PublicationYear,
    b.IsAvailable
FROM 
    Books b
JOIN 
    Authors a ON b.AuthorID = a.AuthorID;


-- Exemplos de uso

-- Inserindo autores
INSERT INTO Authors (Name, BirthDate, Nationality) VALUES 
('George Orwell', '1903-06-25', 'British'),
('Harper Lee', '1926-04-28', 'American');

-- Inserindo livros
INSERT INTO Books (Title, AuthorID, Genre, PublicationYear) VALUES 
('1984', 1, 'Dystopian', 1949),
('To Kill a Mockingbird', 2, 'Fiction', 1960);

-- Inserindo membros
INSERT INTO Members (Name, Email, Phone) VALUES 
('John Doe', 'john@example.com', '1234567890'),
('Jane Smith', 'jane@example.com', '0987654321');

-- Registrando um empréstimo
INSERT INTO Loans (BookID, MemberID, DueDate) VALUES 
(1, 1, DATE_ADD(CURRENT_DATE, INTERVAL 14 DAY));

-- Atualizando a devolução de um livro
UPDATE Loans SET ReturnDate = CURRENT_DATE WHERE LoanID = 1;

-- Consultando livros com autores
SELECT * FROM BooksWithAuthors;

-- Consultando empréstimos ativos
SELECT * FROM ActiveLoans;
