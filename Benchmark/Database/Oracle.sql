CREATE TABLE Post
(
	id RAW(16) PRIMARY KEY,
	title VARCHAR2(4000) NOT NULL,
	created DATE NOT NULL
);

CREATE INDEX IX_Post_created ON Post(created);

CREATE TABLE Invoice
(
	"number" VARCHAR2(20) PRIMARY KEY,
	dueDate DATE NOT NULL,
	total NUMBER(15,2) NOT NULL,
	paid TIMESTAMP WITH TIME ZONE,
	canceled CHAR(1) NOT NULL,
	version NUMBER(20,0) NOT NULL,
	tax NUMBER(15,2) NOT NULL,
	reference VARCHAR2(15),
	createdAt TIMESTAMP WITH TIME ZONE NOT NULL,
	modifiedAt TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IX_Invoice_version ON Invoice(version);
CREATE INDEX IX_Invoice_createdAt ON Invoice(createdAt);

CREATE TABLE Item
(
	InvoiceNumber VARCHAR2(20),
	"Index" NUMBER(10, 0),
	PRIMARY KEY(InvoiceNumber, "Index"),
	FOREIGN KEY(InvoiceNumber) REFERENCES Invoice("number") ON DELETE CASCADE,
	product VARCHAR2(100) NOT NULL,
	cost NUMBER(15,2) NOT NULL,
	quantity NUMBER(10,0) NOT NULL,
	taxGroup NUMBER(5,1) NOT NULL,
	discount NUMBER(5,2) NOT NULL
);
