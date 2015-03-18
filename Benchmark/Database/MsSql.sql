CREATE TABLE Post
(
	id UNIQUEIDENTIFIER PRIMARY KEY,
	title VARCHAR(MAX) NOT NULL,
	created DATE NOT NULL
)

CREATE INDEX IX_Post_created ON Post(created)

CREATE TABLE Invoice
(
	number VARCHAR(20) PRIMARY KEY,
	dueDate DATE NOT NULL,
	total DECIMAL(15,2) NOT NULL,
	paid DATETIME,
	canceled BIT NOT NULL,
	version BIGINT NOT NULL,
	tax DECIMAL(15,2) NOT NULL,
	reference VARCHAR(15),
	createdAt DATETIME NOT NULL,
	modifiedAt DATETIME NOT NULL
)

CREATE INDEX IX_Invoice_version ON Invoice(version)
CREATE INDEX IX_Invoice_createdAt ON Invoice(createdAt)

CREATE TABLE Item
(
	InvoiceNumber VARCHAR(20),
	[Index] INT,
	PRIMARY KEY(InvoiceNumber, [Index]),
	FOREIGN KEY(InvoiceNumber) REFERENCES Invoice(number) ON UPDATE CASCADE ON DELETE CASCADE,
	product VARCHAR(100) NOT NULL,
	cost DECIMAL(15,2) NOT NULL,
	quantity INT NOT NULL,
	taxGroup DECIMAL(5,1) NOT NULL,
	discount DECIMAL(5,2) NOT NULL
)

CREATE TABLE BankScrape
(
	id INT PRIMARY KEY,
	website VARCHAR(1024) NOT NULL,
	at DATETIME NOT NULL,
	info VARCHAR(MAX),
	externalId VARCHAR(50),
	ranking INT NOT NULL,
	tags VARCHAR(MAX),
	createdAt DATETIME NOT NULL
)

CREATE INDEX IX_BankScrape_createdAt ON BankScrape(createdAt)

CREATE TABLE Currency ( value VARCHAR(100) PRIMARY KEY )

INSERT INTO Currency VALUES('EUR')
INSERT INTO Currency VALUES('USD')
INSERT INTO Currency VALUES('Other')

CREATE TABLE Account
(
  BankScrapeId INT,
  [Index] INT,
  PRIMARY KEY(BankScrapeId, [Index]),
  FOREIGN KEY (BankScrapeId) REFERENCES BankScrape (id) ON UPDATE CASCADE ON DELETE CASCADE,
  balance DECIMAL(15,2) NOT NULL,
  number VARCHAR(40) NOT NULL,
  name VARCHAR(100) NOT NULL,
  notes VARCHAR(800) NOT NULL
)

CREATE TABLE [Transaction]
(
  AccountBankScrapeId INT,
  AccountIndex INT,
  [Index] INT,
  PRIMARY KEY(AccountBankScrapeId, AccountIndex, [Index]),
  FOREIGN KEY (AccountBankScrapeId, AccountIndex) REFERENCES Account (BankScrapeId, [Index]) ON UPDATE CASCADE ON DELETE CASCADE,
  date DATE NOT NULL,
  description VARCHAR(200) NOT NULL,
  currency VARCHAR(100),
  FOREIGN KEY (currency) REFERENCES Currency(value) ON UPDATE CASCADE,
  amount DECIMAL(15,2) NOT NULL
)
