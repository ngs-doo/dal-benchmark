using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;

namespace Benchmark
{
	class MsSqlBench
	{
		private static string ConnectionString = ConfigurationManager.AppSettings["MsSqlConnectionString"];

		static void RunQuery(string query)
		{
			using (var conn = new SqlConnection(ConnectionString))
			{
				var com = conn.CreateCommand();
				com.CommandText = query;
				conn.Open();
				var tran = conn.BeginTransaction();
				com.Transaction = tran;
				com.ExecuteNonQuery();
				tran.Commit();
				conn.Close();
			}
		}

		internal static void Run(BenchType type, int data)
		{
			var conn = new SqlConnection(ConnectionString);
			conn.Open();
			switch (type)
			{
				case BenchType.Simple:
					Program.RunBenchmark(
						new SimpleBench(conn),
						Factories.NewSimple,
						Factories.UpdateSimple,
						null,
						data);
					break;
				case BenchType.Standard_Relations:
					Program.RunBenchmark(
						new StandardBench(conn),
						StandardBench.NewStandard,
						Factories.UpdateStandard,
						null,
						data);
					break;
				case BenchType.Complex_Relations:
					Program.RunBenchmark(
						new ComplexBench(conn),
						ComplexBench.NewComplex,
						Factories.UpdateComplex,
						null,
						data);
					break;
				default:
					throw new NotSupportedException("not supported");
			}
		}

		class SimpleBench : IBench<Simple.Post>
		{
			private readonly SqlConnection Conn;
			private readonly DateTime Today = Factories.Today;

			public SimpleBench(SqlConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM Post");
			}

			public void Analyze()
			{
				RunQuery("UPDATE STATISTICS Post");
			}

			private static Simple.Post PostFactory(SqlDataReader reader)
			{
				var post = new Simple.Post { id = reader.GetGuid(0), title = reader.GetString(1), created = reader.GetDateTime(2) };
				ChangeURI.Change(post, post.id.ToString());
				return post;
			}

			private static Simple.Post ExecuteSingle(SqlCommand com)
			{
				using (var reader = com.ExecuteReader())
				{
					if (reader.Read())
						return PostFactory(reader);
					return null;
				}
			}

			private static List<Simple.Post> ExecuteCollection(SqlCommand com)
			{
				using (var reader = com.ExecuteReader())
					return ExtractCollection(reader);
			}

			private static List<Simple.Post> ExtractCollection(SqlDataReader reader)
			{
				var tmp = new List<Simple.Post>();
				while (reader.Read())
					tmp.Add(PostFactory(reader));
				return tmp;
			}

			public IEnumerable<Simple.Post> SearchAll()
			{
				using (var com = Conn.CreateCommand())
				{
					com.CommandText = "SELECT id, title, created FROM Post";
					return ExecuteCollection(com);
				}
			}

			public IEnumerable<Simple.Post> SearchSubset(int i)
			{
				using (var com = Conn.CreateCommand())
				{
					com.CommandText = "SELECT id, title, created FROM Post p WHERE p.created >= @from AND p.created <= @until";
					com.Parameters.AddWithValue("from", Today.AddDays(i));
					com.Parameters.AddWithValue("until", Today.AddDays(i + 10));
					return ExecuteCollection(com);
				}
			}

			public System.Linq.IQueryable<Simple.Post> Query()
			{
				return null;
			}

			public Simple.Post FindSingle(string id)
			{
				using (var com = Conn.CreateCommand())
				{
					//TODO: slower with params
					com.CommandText = "SELECT title, created FROM Post WHERE id = @id";
					var guid = Guid.Parse(id);
					com.Parameters.AddWithValue("id", guid);
					using (var reader = com.ExecuteReader())
					{
						if (reader.Read())
						{
							var post = new Simple.Post { id = guid, title = reader.GetString(0), created = reader.GetDateTime(1) };
							ChangeURI.Change(post, id);
							return post;
						}
					}
				}
				return null;
			}

			public IEnumerable<Simple.Post> FindMany(string[] ids)
			{
				using (var com = Conn.CreateCommand())
				{
					//TODO: Twice as slow with params
					com.CommandText = "SELECT id, title, created FROM Post WHERE id IN ('" + string.Join("','", ids) + "')";
					return ExecuteCollection(com);
				}
			}

			public void Insert(IEnumerable<Simple.Post> values)
			{
				var table = new DataTable();
				table.Columns.Add("id", typeof(Guid));
				table.Columns.Add("title", typeof(string));
				table.Columns.Add("created", typeof(DateTime));
				table.PrimaryKey = new[] { table.Columns[0] };
				foreach (var v in values)
					table.Rows.Add(v.id, v.title, v.created);
				var tran = Conn.BeginTransaction();
				var copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
				copy.DestinationTableName = "Post";
				copy.WriteToServer(table);
				tran.Commit();
				foreach (var v in values)
					ChangeURI.Change(v, v.id.ToString());
			}

			public void Update(IEnumerable<Simple.Post> values)
			{
				var table = new DataTable();
				table.Columns.Add("id", typeof(Guid));
				table.Columns.Add("title", typeof(string));
				table.Columns.Add("created", typeof(DateTime));
				table.Columns.Add("uri", typeof(Guid));
				foreach (var v in values)
					table.Rows.Add(v.id, v.title, v.created, Guid.Parse(v.URI));
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.Transaction = tran;
					com.CommandText = "CREATE TABLE #Tmp ( id UNIQUEIDENTIFIER, title VARCHAR(MAX), created DATE, uri UNIQUEIDENTIFIER )";
					com.ExecuteNonQuery();
					var copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
					copy.DestinationTableName = "#Tmp";
					copy.WriteToServer(table);
					com.CommandText = @"
UPDATE Post SET id = t.id, title = t.title, created = t.created FROM #Tmp t WHERE Post.id = t.uri;
DROP TABLE #Tmp";
					com.ExecuteNonQuery();
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.id.ToString());
				}
			}

			public void Insert(Simple.Post value)
			{
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.Transaction = tran;
					com.CommandText = "INSERT INTO Post(id, title, created) VALUES(@id, @title, @created)";
					com.Parameters.AddWithValue("id", value.id);
					com.Parameters.AddWithValue("title", value.title);
					com.Parameters.AddWithValue("created", value.created);
					com.ExecuteNonQuery();
					tran.Commit();
					ChangeURI.Change(value, value.id.ToString());
				}
			}

			public void Update(Simple.Post value)
			{
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.Transaction = tran;
					com.CommandText = "UPDATE Post SET id = @id, title = @title, created = @created WHERE id = @uri";
					com.Parameters.AddWithValue("id", value.id);
					com.Parameters.AddWithValue("title", value.title);
					com.Parameters.AddWithValue("created", value.created);
					com.Parameters.AddWithValue("uri", Guid.Parse(value.URI));
					com.ExecuteNonQuery();
					tran.Commit();
					ChangeURI.Change(value, value.id.ToString());
				}
			}

			public Report<Simple.Post> Report(int i)
			{
				Func<int, Guid> gg = Factories.GetGuid;
				var result = new Report<Simple.Post>();
				var id = gg(i);
				var ids = new[] { gg(i), gg(i + 2), gg(i + 5), gg(i + 7) };
				var start = Today.AddDays(i);
				var end = Today.AddDays(i + 6);
				using (var com = Conn.CreateCommand())
				{
					com.CommandText = @"
SELECT id, title, created FROM Post WHERE id = @id;
SELECT id, title, created FROM Post WHERE id IN (@id1, @id2, @id3, @id4);
SELECT TOP 1 id, title, created FROM Post WHERE created >= @start ORDER BY created ASC;
SELECT TOP 1 id, title, created FROM Post WHERE created <= @end ORDER BY created DESC;
SELECT TOP 5 id, title, created FROM Post WHERE created >= @start AND created <= @end ORDER BY created ASC;
SELECT TOP 10 id, title, created FROM Post WHERE created >= @start AND created <= @end ORDER BY created DESC";
					com.Parameters.AddWithValue("id", id);
					com.Parameters.AddWithValue("id1", ids[0]);
					com.Parameters.AddWithValue("id2", ids[1]);
					com.Parameters.AddWithValue("id3", ids[2]);
					com.Parameters.AddWithValue("id4", ids[3]);
					com.Parameters.AddWithValue("start", start);
					com.Parameters.AddWithValue("end", end);
					using (var reader = com.ExecuteReader())
					{
						if (reader.Read())
							result.findOne = PostFactory(reader);
						reader.NextResult();
						result.findMany = ExtractCollection(reader);
						reader.NextResult();
						if (reader.Read())
							result.findFirst = PostFactory(reader);
						reader.NextResult();
						if (reader.Read())
							result.findLast = PostFactory(reader);
						reader.NextResult();
						result.topFive = ExtractCollection(reader);
						reader.NextResult();
						result.lastTen = ExtractCollection(reader);
					}
				}
				return result;
			}
		}

		class StandardBench : IBench<StandardRelations.Invoice>
		{
			private readonly SqlConnection Conn;

			public StandardBench(SqlConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM Invoice");
			}

			public void Analyze()
			{
				RunQuery("UPDATE STATISTICS Invoice");
				RunQuery("UPDATE STATISTICS Item");
			}

			public static void NewStandard(StandardRelations.Invoice inv, int i)
			{
				Factories.NewStandard<StandardRelations.Item>(inv, i);
				int cnt = 0;
				foreach (var it in inv.items)
				{
					it.Index = cnt++;
					it.Invoicenumber = inv.number;
				}
			}

			private static StandardRelations.Invoice ExecuteSingle(SqlCommand comHead, Func<SqlCommand> lazyChild)
			{
				using (var readerHead = comHead.ExecuteReader())
				{
					return ExtractSingle(readerHead, lazyChild);
				}
			}

			private static StandardRelations.Invoice ExtractSingle(SqlDataReader readerHead, Func<SqlCommand> lazyChild)
			{
				StandardRelations.Invoice invoice = null;
				if (readerHead.Read())
				{
					invoice = new StandardRelations.Invoice
					{
						number = readerHead.GetString(0),
						dueDate = readerHead.GetDateTime(1),
						total = readerHead.GetDecimal(2),
						paid = readerHead.IsDBNull(3) ? null : (DateTime?)readerHead.GetDateTime(3),
						canceled = readerHead.GetBoolean(4),
						version = readerHead.GetInt64(5),
						tax = readerHead.GetDecimal(6),
						reference = readerHead.IsDBNull(7) ? null : readerHead.GetString(7),
						createdAt = readerHead.GetDateTime(8),
						modifiedAt = readerHead.GetDateTime(9)
					};
					ChangeURI.Change(invoice, invoice.number);
				}
				SqlCommand childCom = null;
				SqlDataReader readerChild = null;
				if (lazyChild != null)
				{
					readerHead.Close();
					if (invoice != null)
					{
						childCom = lazyChild();
						//TODO: very slow with params
						childCom.CommandText = "SELECT product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber = '" + invoice.number + "' ORDER BY [Index]";
						readerChild = childCom.ExecuteReader();
					}
				}
				else
				{
					readerHead.NextResult();
					readerChild = readerHead;
				}
				if (readerChild != null)
				{
					while (readerChild.Read())
					{
						invoice.items.Add(new StandardRelations.Item
						{
							Invoicenumber = invoice.number,
							Index = invoice.items.Count,
							product = readerChild.GetString(0),
							cost = readerChild.GetDecimal(1),
							quantity = readerChild.GetInt32(2),
							taxGroup = readerChild.GetDecimal(3),
							discount = readerChild.GetDecimal(4)
						});
					}
					if (lazyChild != null)
						readerChild.Close();
				}
				return invoice;
			}

			private static StandardRelations.Invoice[] ExecuteCollection(SqlCommand comHead, Func<SqlCommand> lazyChild)
			{
				using (var readerHead = comHead.ExecuteReader())
				{
					return ExtractCollection(readerHead, lazyChild);
				}
			}

			private static StandardRelations.Invoice[] ExtractCollection(SqlDataReader readerHead, Func<SqlCommand> lazyChild)
			{
				var map = new Dictionary<string, StandardRelations.Invoice>();
				var order = new Dictionary<string, int>();
				while (readerHead.Read())
				{
					var number = readerHead.GetString(0);
					var invoice = new StandardRelations.Invoice
					{
						number = number,
						dueDate = readerHead.GetDateTime(1),
						total = readerHead.GetDecimal(2),
						paid = readerHead.IsDBNull(3) ? null : (DateTime?)readerHead.GetDateTime(3),
						canceled = readerHead.GetBoolean(4),
						version = readerHead.GetInt64(5),
						tax = readerHead.GetDecimal(6),
						reference = readerHead.IsDBNull(7) ? null : readerHead.GetString(7),
						createdAt = readerHead.GetDateTime(8),
						modifiedAt = readerHead.GetDateTime(9)
					};
					map.Add(number, invoice);
					order.Add(number, order.Count);
					ChangeURI.Change(invoice, invoice.number);
				}
				SqlCommand childCom = null;
				SqlDataReader readerChild = null;
				if (lazyChild != null)
				{
					readerHead.Close();
					if (map.Count > 0)
					{
						childCom = lazyChild();
						//TODO: very slow with params
						childCom.CommandText = "SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN ('" + string.Join("','", map.Keys) + "') ORDER BY Invoicenumber, [Index]";
						readerChild = childCom.ExecuteReader();
					}
				}
				else
				{
					readerHead.NextResult();
					readerChild = readerHead;
				}
				if (readerChild != null)
				{
					while (readerChild.Read())
					{
						var number = readerChild.GetString(0);
						var items = map[number].items;
						items.Add(new StandardRelations.Item
						{
							Invoicenumber = number,
							Index = items.Count,
							product = readerChild.GetString(1),
							cost = readerChild.GetDecimal(2),
							quantity = readerChild.GetInt32(3),
							taxGroup = readerChild.GetDecimal(4),
							discount = readerChild.GetDecimal(5)
						});
					}
					if (lazyChild != null)
						readerChild.Close();
				}
				var result = new StandardRelations.Invoice[map.Count];
				foreach (var kv in order)
					result[kv.Value] = map[kv.Key];
				return result;
			}

			public IEnumerable<StandardRelations.Invoice> SearchAll()
			{
				using (var comHead = Conn.CreateCommand())
				{
					comHead.CommandText = @"
SELECT number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice ORDER BY number;
SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item ORDER BY Invoicenumber, [Index]";
					return ExecuteCollection(comHead, null);
				}
			}

			public IEnumerable<StandardRelations.Invoice> SearchSubset(int i)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= @start AND version <= @end ORDER BY number";
					comHead.Parameters.AddWithValue("start", i);
					comHead.Parameters.AddWithValue("end", i + 10);
					return ExecuteCollection(comHead, () => comChild);
				}
			}

			public System.Linq.IQueryable<StandardRelations.Invoice> Query()
			{
				return null;
			}

			public StandardRelations.Invoice FindSingle(string id)
			{
				using (var comHead = Conn.CreateCommand())
				{
					//TODO: very slow with params
					comHead.CommandText = @"
SELECT number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE number = '" + id + @"';
SELECT product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber = '" + id + "' ORDER BY [Index]";
					return ExecuteSingle(comHead, null);
				}
			}

			public IEnumerable<StandardRelations.Invoice> FindMany(string[] ids)
			{
				using (var comHead = Conn.CreateCommand())
				{
					//TODO: very slow with params
					var inSql = "'" + string.Join("','", ids) + "'";
					comHead.CommandText = @"SELECT number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE number IN (" + inSql + @") ORDER BY number;
SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN (" + inSql + ") ORDER BY Invoicenumber, [Index]";
					return ExecuteCollection(comHead, null);
				}
			}

			public void Insert(IEnumerable<StandardRelations.Invoice> values)
			{
				var tableHead = new DataTable();
				var tableChild = new DataTable();
				tableHead.Columns.Add("number", typeof(string));
				tableHead.Columns.Add("dueDate", typeof(DateTime));
				tableHead.Columns.Add("total", typeof(decimal));
				tableHead.Columns.Add("paid", typeof(DateTime));
				tableHead.Columns.Add("canceled", typeof(bool));
				tableHead.Columns.Add("version", typeof(int));
				tableHead.Columns.Add("tax", typeof(decimal));
				tableHead.Columns.Add("reference", typeof(string));
				tableHead.Columns.Add("createdAt", typeof(DateTime));
				tableHead.Columns.Add("modifiedAt", typeof(DateTime));
				tableHead.PrimaryKey = new[] { tableHead.Columns[0] };
				tableChild.Columns.Add("Invoicenumber", typeof(string));
				tableChild.Columns.Add("Index", typeof(int));
				tableChild.Columns.Add("product", typeof(string));
				tableChild.Columns.Add("cost", typeof(decimal));
				tableChild.Columns.Add("quantity", typeof(int));
				tableChild.Columns.Add("taxGroup", typeof(decimal));
				tableChild.Columns.Add("discount", typeof(decimal));
				tableChild.PrimaryKey = new[] { tableChild.Columns[0], tableChild.Columns[1] };
				foreach (var v in values)
				{
					tableHead.Rows.Add(v.number, v.dueDate, v.total, (object)v.paid ?? DBNull.Value, v.canceled, v.version, v.total, (object)v.reference ?? DBNull.Value, v.createdAt, v.modifiedAt);
					foreach (var d in v.items)
						tableChild.Rows.Add(d.Invoicenumber, d.Index, d.product, d.cost, d.quantity, d.taxGroup, d.discount);
				}
				var tran = Conn.BeginTransaction();
				var copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
				copy.DestinationTableName = "Invoice";
				copy.WriteToServer(tableHead);
				copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
				copy.DestinationTableName = "Item";
				copy.WriteToServer(tableChild);
				tran.Commit();
				foreach (var v in values)
					ChangeURI.Change(v, v.number);
			}

			public void Update(IEnumerable<StandardRelations.Invoice> values)
			{
				var tableHead = new DataTable();
				var tableChild = new DataTable();
				tableHead.Columns.Add("uri", typeof(string));
				tableHead.Columns.Add("size", typeof(int));
				tableHead.Columns.Add("number", typeof(string));
				tableHead.Columns.Add("dueDate", typeof(DateTime));
				tableHead.Columns.Add("total", typeof(decimal));
				tableHead.Columns.Add("paid", typeof(DateTime));
				tableHead.Columns.Add("canceled", typeof(bool));
				tableHead.Columns.Add("version", typeof(int));
				tableHead.Columns.Add("tax", typeof(decimal));
				tableHead.Columns.Add("reference", typeof(string));
				tableHead.Columns.Add("modifiedAt", typeof(DateTime));
				tableHead.PrimaryKey = new[] { tableHead.Columns[0] };
				tableChild.Columns.Add("number", typeof(string));
				tableChild.Columns.Add("i", typeof(int));
				tableChild.Columns.Add("product", typeof(string));
				tableChild.Columns.Add("cost", typeof(decimal));
				tableChild.Columns.Add("quantity", typeof(int));
				tableChild.Columns.Add("taxGroup", typeof(decimal));
				tableChild.Columns.Add("discount", typeof(decimal));
				tableChild.PrimaryKey = new[] { tableChild.Columns[0], tableChild.Columns[1] };
				foreach (var v in values)
				{
					tableHead.Rows.Add(v.URI, v.items.Count, v.number, v.dueDate, v.total, (object)v.paid ?? DBNull.Value, v.canceled, v.version, v.total, (object)v.reference ?? DBNull.Value, v.modifiedAt);
					foreach (var d in v.items)
						tableChild.Rows.Add(d.Invoicenumber, d.Index, d.product, d.cost, d.quantity, d.taxGroup, d.discount);
				}
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.Transaction = tran;
					com.CommandText = @"
CREATE TABLE #Invoice 
( 
	uri VARCHAR(20) PRIMARY KEY,
	size INT NOT NULL,
	number VARCHAR(20) NOT NULL,
	dueDate DATE NOT NULL,
	total DECIMAL(15,2) NOT NULL,
	paid DATETIME,
	canceled BIT NOT NULL,
	version BIGINT NOT NULL,
	tax DECIMAL(15,2) NOT NULL,
	reference VARCHAR(15),
	modifiedAt DATETIME NOT NULL
);
CREATE TABLE #Item
(
	number VARCHAR(20),
	i INT,
	PRIMARY KEY(number, i),
	product VARCHAR(100) NOT NULL,
	cost DECIMAL(15,2) NOT NULL,
	quantity INT NOT NULL,
	taxGroup DECIMAL(5,1) NOT NULL,
	discount DECIMAL(5,2) NOT NULL
)
";
					com.ExecuteNonQuery();
					var copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
					copy.DestinationTableName = "#Invoice";
					copy.WriteToServer(tableHead);
					copy.DestinationTableName = "#Item";
					copy.WriteToServer(tableChild);
					com.CommandText = @"
UPDATE i SET number = t.number, dueDate = t.dueDate, total = t.total, paid = t.paid, canceled = t.canceled, version = t.version, tax = t.tax, reference = t.reference, modifiedAt = t.modifiedAt 
FROM Invoice i
INNER JOIN #Invoice t ON i.number = t.uri;
DELETE i 
FROM Item i 
INNER JOIN #Invoice t ON i.Invoicenumber = t.number AND i.[Index] > t.size;
UPDATE i SET product = t.product, cost = t.cost, quantity = t.quantity, taxGroup = t.taxGroup, discount = t.discount 
FROM Item i
INNER JOIN #Item t ON i.invoiceNumber = t.number AND i.[Index] = t.i;
INSERT INTO Item(Invoicenumber, [Index], product, cost, quantity, taxGroup, discount) 
SELECT t.number, t.i, t.product, t.cost, t.quantity, t.taxGroup, t.discount
FROM #Item t
LEFT JOIN Item i ON i.invoiceNumber = t.number AND i.[Index] = t.i
WHERE i.invoiceNumber IS NULL;
DROP TABLE #Invoice;
DROP TABLE #Item";
					com.ExecuteNonQuery();
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.number);
				}
			}

			public void Insert(StandardRelations.Invoice item)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comHead.CommandText = "INSERT INTO Invoice(number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt) VALUES(@number, @dueDate, @total, @paid, @canceled, @version, @tax, @reference, @createdAt, @modifiedAt)";
					comChild.CommandText = "INSERT INTO Item(Invoicenumber, [Index], product, cost, quantity, taxGroup, discount) VALUES(@number, @index, @product, @cost, @quantity, @taxGroup, @discount)";
					comHead.Transaction = tran;
					comChild.Transaction = tran;
					var ph1 = new SqlParameter("number", DbType.String);
					var ph2 = new SqlParameter("dueDate", DbType.Date);
					var ph3 = new SqlParameter("total", DbType.Decimal);
					var ph4 = new SqlParameter("paid", DbType.DateTime);
					var ph5 = new SqlParameter("canceled", DbType.Boolean);
					var ph6 = new SqlParameter("version", DbType.Int64);
					var ph7 = new SqlParameter("tax", DbType.Decimal);
					var ph8 = new SqlParameter("reference", DbType.String);
					var ph9 = new SqlParameter("createdAt", DbType.DateTime);
					var ph10 = new SqlParameter("modifiedAt", DbType.DateTime);
					var pc1 = new SqlParameter("number", DbType.String);
					var pc2 = new SqlParameter("index", DbType.Int32);
					var pc3 = new SqlParameter("product", DbType.String);
					var pc4 = new SqlParameter("cost", DbType.Decimal);
					var pc5 = new SqlParameter("quantity", DbType.Int32);
					var pc6 = new SqlParameter("taxGroup", DbType.Decimal);
					var pc7 = new SqlParameter("discount", DbType.Decimal);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8, ph9, ph10 });
					comChild.Parameters.AddRange(new[] { pc1, pc2, pc3, pc4, pc5, pc6, pc7 });
					ph1.Value = item.number;
					ph2.Value = item.dueDate;
					ph3.Value = item.total;
					ph4.Value = (object)item.paid ?? DBNull.Value;
					ph5.Value = item.canceled;
					ph6.Value = item.version;
					ph7.Value = item.tax;
					ph8.Value = (object)item.reference ?? DBNull.Value;
					ph9.Value = item.createdAt;
					ph10.Value = item.modifiedAt;
					comHead.ExecuteNonQuery();
					for (int i = 0; i < item.items.Count; i++)
					{
						var ch = item.items[i];
						pc1.Value = item.number;
						pc2.Value = i;
						pc3.Value = ch.product;
						pc4.Value = ch.cost;
						pc5.Value = ch.quantity;
						pc6.Value = ch.taxGroup;
						pc7.Value = ch.discount;
						comChild.ExecuteNonQuery();
					}
					tran.Commit();
				}
				ChangeURI.Change(item, item.number);
			}

			public void Update(StandardRelations.Invoice item)
			{
				using (var comInfo = Conn.CreateCommand())
				using (var comHead = Conn.CreateCommand())
				using (var comChildInsert = Conn.CreateCommand())
				using (var comChildUpdate = Conn.CreateCommand())
				using (var comChildDelete = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comInfo.CommandText = "SELECT COALESCE(MAX([Index]), -1) FROM Item WHERE Invoicenumber = @uri";
					comHead.CommandText = "UPDATE Invoice SET number = @number, dueDate = @dueDate, total = @total, paid = @paid, canceled = @canceled, version = @version, tax = @tax, reference = @reference, modifiedAt = @modifiedAt WHERE number = @uri";
					comChildInsert.CommandText = "INSERT INTO Item(Invoicenumber, [Index], product, cost, quantity, taxGroup, discount) VALUES(@number, @index, @product, @cost, @quantity, @taxGroup, @discount)";
					comChildUpdate.CommandText = "UPDATE Item SET product = @product, cost = @cost, quantity = @quantity, taxGroup = @taxGroup, discount = @discount WHERE Invoicenumber = @number AND [Index] = @index";
					comChildDelete.CommandText = "DELETE FROM Item WHERE Invoicenumber = @uri AND [Index] > @index";
					comInfo.Transaction = tran;
					comHead.Transaction = tran;
					comChildInsert.Transaction = tran;
					comChildUpdate.Transaction = tran;
					comChildDelete.Transaction = tran;
					var puri = new SqlParameter("uri", DbType.String);
					var phuri = new SqlParameter("uri", DbType.String);
					var ph1 = new SqlParameter("number", DbType.String);
					var ph2 = new SqlParameter("dueDate", DbType.Date);
					var ph3 = new SqlParameter("total", DbType.Decimal);
					var ph4 = new SqlParameter("paid", DbType.DateTime);
					var ph5 = new SqlParameter("canceled", DbType.Boolean);
					var ph6 = new SqlParameter("version", DbType.Int64);
					var ph7 = new SqlParameter("tax", DbType.Decimal);
					var ph8 = new SqlParameter("reference", DbType.String);
					var ph9 = new SqlParameter("modifiedAt", DbType.DateTime);
					var pci1 = new SqlParameter("number", DbType.String);
					var pci2 = new SqlParameter("index", DbType.Int32);
					var pci3 = new SqlParameter("product", DbType.String);
					var pci4 = new SqlParameter("cost", DbType.Decimal);
					var pci5 = new SqlParameter("quantity", DbType.Int32);
					var pci6 = new SqlParameter("taxGroup", DbType.Decimal);
					var pci7 = new SqlParameter("discount", DbType.Decimal);
					var pcu1 = new SqlParameter("number", DbType.String);
					var pcu2 = new SqlParameter("index", DbType.Int32);
					var pcu3 = new SqlParameter("product", DbType.String);
					var pcu4 = new SqlParameter("cost", DbType.Decimal);
					var pcu5 = new SqlParameter("quantity", DbType.Int32);
					var pcu6 = new SqlParameter("taxGroup", DbType.Decimal);
					var pcu7 = new SqlParameter("discount", DbType.Decimal);
					var pcd1 = new SqlParameter("number", DbType.String);
					var pcd2 = new SqlParameter("index", DbType.Int32);
					comInfo.Parameters.Add(puri);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8, ph9, phuri });
					comChildInsert.Parameters.AddRange(new[] { pci1, pci2, pci3, pci4, pci5, pci6, pci7 });
					comChildUpdate.Parameters.AddRange(new[] { pcu1, pcu2, pcu3, pcu4, pcu5, pcu6, pcu7 });
					comChildDelete.Parameters.AddRange(new[] { pcd1, pcd2 });
					puri.Value = item.URI;
					phuri.Value = item.URI;
					var max = (int)comInfo.ExecuteScalar();
					ph1.Value = item.number;
					ph2.Value = item.dueDate;
					ph3.Value = item.total;
					ph4.Value = (object)item.paid ?? DBNull.Value;
					ph5.Value = item.canceled;
					ph6.Value = item.version;
					ph7.Value = item.tax;
					ph8.Value = (object)item.reference ?? DBNull.Value;
					ph9.Value = item.modifiedAt;
					comHead.ExecuteNonQuery();
					var min = Math.Min(max, item.items.Count);
					for (int i = 0; i <= min; i++)
					{
						var ch = item.items[i];
						pcu1.Value = item.number;
						pcu2.Value = i;
						pcu3.Value = ch.product;
						pcu4.Value = ch.cost;
						pcu5.Value = ch.quantity;
						pcu6.Value = ch.taxGroup;
						pcu7.Value = ch.discount;
						comChildUpdate.ExecuteNonQuery();
					}
					for (int i = min + 1; i < item.items.Count; i++)
					{
						var ch = item.items[i];
						pci1.Value = item.number;
						pci2.Value = i;
						pci3.Value = ch.product;
						pci4.Value = ch.cost;
						pci5.Value = ch.quantity;
						pci6.Value = ch.taxGroup;
						pci7.Value = ch.discount;
						comChildInsert.ExecuteNonQuery();
					}
					if (max > item.items.Count)
					{
						pcd1.Value = item.number;
						pcd2.Value = max;
						comChildDelete.ExecuteNonQuery();
					}
					tran.Commit();
					ChangeURI.Change(item, item.number);
				}
			}

			public Report<StandardRelations.Invoice> Report(int i)
			{
				var result = new Report<StandardRelations.Invoice>();
				var id = i.ToString();
				var ids = new[] { i.ToString(), (i + 2).ToString(), (i + 5).ToString(), (i + 7).ToString() };
				var start = i;
				var end = i + 6;
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					var inSql = string.Join("','", ids);
					comHead.CommandText = @"
SELECT number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE number = '" + id + @"';
SELECT product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber = '" + id + @"' ORDER BY [Index];
SELECT number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE number IN ('" + inSql + @"') ORDER BY number;
SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN ('" + inSql + @"') ORDER BY Invoicenumber, [Index];
SELECT TOP 1 number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= @start ORDER BY createdAt";
					comHead.Parameters.AddWithValue("start", start);
					using (var reader = comHead.ExecuteReader())
					{
						result.findOne = ExtractSingle(reader, null);
						reader.NextResult();
						result.findMany = ExtractCollection(reader, null);
						reader.NextResult();
						result.findFirst = ExtractSingle(reader, () => comChild);
					}
					comHead.CommandText = "SELECT TOP 1 number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version <= @end ORDER BY createdAt DESC";
					comHead.Parameters.Clear();
					comHead.Parameters.AddWithValue("end", end);
					result.findLast = ExecuteSingle(comHead, () => comChild);
					comHead.CommandText = "SELECT TOP 5 number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= @start AND version <= @end ORDER BY createdAt, number";
					comHead.Parameters.Clear();
					comHead.Parameters.AddWithValue("start", start);
					comHead.Parameters.AddWithValue("end", end);
					result.topFive = ExecuteCollection(comHead, () => comChild);
					comHead.CommandText = "SELECT TOP 10 number, dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= @start AND version <= @end ORDER BY createdAt DESC, number";
					result.lastTen = ExecuteCollection(comHead, () => comChild);
				}
				return result;
			}
		}

		class ComplexBench : IBench<ComplexRelations.BankScrape>
		{
			private readonly SqlConnection Conn;
			private readonly DateTime Now = Factories.Now;

			public ComplexBench(SqlConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM BankScrape");
			}

			public void Analyze()
			{
				RunQuery("UPDATE STATISTICS BankScrape");
				RunQuery("UPDATE STATISTICS Account");
				RunQuery("UPDATE STATISTICS [Transaction]");
			}

			public static void NewComplex(ComplexRelations.BankScrape scrape, int i)
			{
				Factories.NewComplex<ComplexRelations.Account, ComplexRelations.Transaction>(scrape, i);
				int cntAcc = 0;
				foreach (var acc in scrape.accounts)
				{
					acc.Index = cntAcc++;
					acc.BankScrapeid = scrape.id;
					int cntTran = 0;
					foreach (var tr in acc.transactions)
					{
						tr.AccountBankScrapeid = scrape.id;
						tr.AccountIndex = acc.Index;
						tr.Index = cntTran++;
					}
				}
			}

			private static ComplexRelations.BankScrape ExecuteSingle(
				SqlCommand comHead,
				Func<string, SqlCommand> childFactory,
				Func<string, SqlCommand> detailFactory)
			{
				ComplexRelations.BankScrape scrape = null;
				using (var readerHead = comHead.ExecuteReader())
				{
					if (readerHead.Read())
					{
						scrape = new ComplexRelations.BankScrape
						{
							id = readerHead.GetInt32(0),
							website = new System.Uri(readerHead.GetString(1)),
							at = readerHead.GetDateTime(2),
							info = Revenj.DatabasePersistence.Postgres.Converters.HstoreConverter.FromDatabase(readerHead.GetString(3)),
							externalId = readerHead.IsDBNull(4) ? null : readerHead.GetString(4),
							ranking = readerHead.GetInt32(5),
							tags = new HashSet<string>(readerHead.GetString(6).Split(',')),
							createdAt = readerHead.GetDateTime(7)
						};
						ChangeURI.Change(scrape, scrape.id.ToString());
					}
				}
				if (scrape != null)
				{
					using (var childCom = childFactory(scrape.URI))
					using (var readerChild = childCom.ExecuteReader())
					{
						while (readerChild.Read())
						{
							scrape.accounts.Add(new ComplexRelations.Account
							{
								BankScrapeid = scrape.id,
								Index = scrape.accounts.Count,
								balance = readerChild.GetDecimal(0),
								number = readerChild.GetString(1),
								name = readerChild.GetString(2),
								notes = readerChild.GetString(3)
							});
						}
					}
					using (var detailCom = detailFactory(scrape.URI))
					using (var readerDetail = detailCom.ExecuteReader())
					{
						while (readerDetail.Read())
						{
							var index = readerDetail.GetInt32(0);
							var acc = scrape.accounts[index];
							acc.transactions.Add(new ComplexRelations.Transaction
							{
								AccountBankScrapeid = scrape.id,
								AccountIndex = index,
								Index = acc.transactions.Count,
								date = readerDetail.GetDateTime(1),
								description = readerDetail.GetString(2),
								currency = (Complex.Currency)Enum.Parse(typeof(Complex.Currency), readerDetail.GetString(3)),
								amount = readerDetail.GetDecimal(4)
							});
						}
					}
				}
				return scrape;
			}

			private static ComplexRelations.BankScrape[] ExecuteCollection(
				SqlCommand comHead,
				Func<IEnumerable<string>, SqlCommand> childFactory,
				Func<IEnumerable<string>, SqlCommand> detailFactory)
			{
				var map = new Dictionary<string, ComplexRelations.BankScrape>();
				var order = new Dictionary<int, int>();
				using (var readerHead = comHead.ExecuteReader())
				{
					while (readerHead.Read())
					{
						var id = readerHead.GetInt32(0);
						var scrape = new ComplexRelations.BankScrape
						{
							id = id,
							website = new System.Uri(readerHead.GetString(1)),
							at = readerHead.GetDateTime(2),
							info = Revenj.DatabasePersistence.Postgres.Converters.HstoreConverter.FromDatabase(readerHead.GetString(3)),
							externalId = readerHead.IsDBNull(4) ? null : readerHead.GetString(4),
							ranking = readerHead.GetInt32(5),
							tags = new HashSet<string>(readerHead.GetString(6).Split(',')),
							createdAt = readerHead.GetDateTime(7)
						};
						ChangeURI.Change(scrape, scrape.id.ToString());
						map.Add(scrape.URI, scrape);
						order.Add(id, order.Count);
					}
					readerHead.Close();
				}
				if (map.Count > 0)
				{
					using (var childCom = childFactory(map.Keys))
					using (var readerChild = childCom.ExecuteReader())
					{
						while (readerChild.Read())
						{
							var id = readerChild.GetInt32(0);
							var accounts = map[id.ToString()].accounts;
							accounts.Add(new ComplexRelations.Account
							{
								BankScrapeid = id,
								Index = accounts.Count,
								balance = readerChild.GetDecimal(1),
								number = readerChild.GetString(2),
								name = readerChild.GetString(3),
								notes = readerChild.GetString(4)
							});
						}
					}
					using (var detailCom = detailFactory(map.Keys))
					using (var readerDetail = detailCom.ExecuteReader())
					{
						while (readerDetail.Read())
						{
							var id = readerDetail.GetInt32(0);
							var accounts = map[id.ToString()].accounts;
							var index = readerDetail.GetInt32(1);
							var tran = accounts[index].transactions;
							tran.Add(new ComplexRelations.Transaction
							{
								AccountBankScrapeid = id,
								AccountIndex = index,
								Index = tran.Count,
								date = readerDetail.GetDateTime(2),
								description = readerDetail.GetString(3),
								currency = (Complex.Currency)Enum.Parse(typeof(Complex.Currency), readerDetail.GetString(4)),
								amount = readerDetail.GetDecimal(5)
							});
						}
					}
				}
				var result = new ComplexRelations.BankScrape[map.Count];
				foreach (var kv in order)
					result[kv.Value] = map[kv.Key.ToString()];
				return result;
			}

			public IEnumerable<ComplexRelations.BankScrape> SearchAll()
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape ORDER BY id";
					comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account ORDER BY BankScrapeid, [Index]";
					comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] ORDER BY AccountBankScrapeid, AccountIndex, [Index]";
					return ExecuteCollection(comHead, _ => comChild, _ => comDetail);
				}
			}

			public IEnumerable<ComplexRelations.BankScrape> SearchSubset(int i)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= @after AND createdAt <= @before ORDER BY id";
					comHead.Parameters.AddWithValue("after", Now.AddMinutes(i));
					comHead.Parameters.AddWithValue("before", Now.AddMinutes(i + 10));
					Func<IEnumerable<string>, SqlCommand> factory1 = nums =>
					{
						comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN ('" + string.Join("','", nums) + "') ORDER BY BankScrapeid, [Index]";
						return comChild;
					};
					Func<IEnumerable<string>, SqlCommand> factory2 = nums =>
					{
						comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN ('" + string.Join("','", nums) + "') ORDER BY AccountBankScrapeid, AccountIndex, [Index]";
						return comDetail;
					};
					return ExecuteCollection(comHead, factory1, factory2);
				}
			}

			public System.Linq.IQueryable<ComplexRelations.BankScrape> Query()
			{
				return null;
			}

			public ComplexRelations.BankScrape FindSingle(string id)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					var pk = int.Parse(id);
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id = @id";
					comHead.Parameters.AddWithValue("id", pk);
					comChild.CommandText = "SELECT balance, number, name, notes FROM Account WHERE BankScrapeid = @id ORDER BY [Index]";
					comChild.Parameters.AddWithValue("id", pk);
					comDetail.CommandText = "SELECT AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid = @id ORDER BY AccountIndex, [Index]";
					comDetail.Parameters.AddWithValue("id", pk);
					return ExecuteSingle(comHead, _ => comChild, _ => comDetail);
				}
			}

			public IEnumerable<ComplexRelations.BankScrape> FindMany(string[] ids)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					//TODO: params as arguments
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id IN (" + string.Join(",", ids) + ") ORDER BY id";
					comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN (" + string.Join(",", ids) + ") ORDER BY BankScrapeid, [Index]";
					comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN (" + string.Join(",", ids) + ") ORDER BY AccountBankScrapeid, AccountIndex, [Index]";
					return ExecuteCollection(comHead, _ => comChild, _ => comDetail);
				}
			}

			public void Insert(IEnumerable<ComplexRelations.BankScrape> values)
			{
				var tableHead = new DataTable();
				var tableChild = new DataTable();
				var tableDetail = new DataTable();
				tableHead.Columns.Add("id", typeof(int));
				tableHead.Columns.Add("website", typeof(string));
				tableHead.Columns.Add("at", typeof(DateTime));
				tableHead.Columns.Add("info", typeof(string));
				tableHead.Columns.Add("externalId", typeof(string));
				tableHead.Columns.Add("ranking", typeof(int));
				tableHead.Columns.Add("tags", typeof(string));
				tableHead.Columns.Add("createdAt", typeof(DateTime));
				tableHead.PrimaryKey = new[] { tableHead.Columns[0] };
				tableChild.Columns.Add("BankScrapeid", typeof(string));
				tableChild.Columns.Add("Index", typeof(int));
				tableChild.Columns.Add("balance", typeof(decimal));
				tableChild.Columns.Add("number", typeof(string));
				tableChild.Columns.Add("name", typeof(string));
				tableChild.Columns.Add("notes", typeof(string));
				tableChild.PrimaryKey = new[] { tableChild.Columns[0], tableChild.Columns[1] };
				tableDetail.Columns.Add("AccountBankScrapeid", typeof(string));
				tableDetail.Columns.Add("AccountIndex", typeof(int));
				tableDetail.Columns.Add("Index", typeof(int));
				tableDetail.Columns.Add("date", typeof(DateTime));
				tableDetail.Columns.Add("description", typeof(string));
				tableDetail.Columns.Add("currency", typeof(string));
				tableDetail.Columns.Add("amount", typeof(decimal));
				tableDetail.PrimaryKey = new[] { tableDetail.Columns[0], tableDetail.Columns[1], tableDetail.Columns[2] };
				foreach (var v in values)
				{
					tableHead.Rows.Add(v.id, v.website.ToString(), v.at, v.info, (object)v.externalId ?? DBNull.Value, v.ranking, string.Join(",", v.tags), v.createdAt);
					foreach (var a in v.accounts)
					{
						tableChild.Rows.Add(a.BankScrapeid, a.Index, a.balance, a.number, a.name, a.notes);
						foreach (var t in a.transactions)
							tableDetail.Rows.Add(t.AccountBankScrapeid, t.AccountIndex, t.Index, t.date, t.description, t.currency.Value.ToString(), t.amount);
					}
				}
				var tran = Conn.BeginTransaction();
				var copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
				copy.DestinationTableName = "BankScrape";
				copy.WriteToServer(tableHead);
				copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
				copy.DestinationTableName = "Account";
				copy.WriteToServer(tableChild);
				copy = new SqlBulkCopy(Conn, SqlBulkCopyOptions.CheckConstraints, tran);
				copy.DestinationTableName = "[Transaction]";
				copy.WriteToServer(tableDetail);
				tran.Commit();
				foreach (var v in values)
					ChangeURI.Change(v, v.id.ToString());
			}

			public void Update(IEnumerable<ComplexRelations.BankScrape> values)
			{
				using (var comInfo = Conn.CreateCommand())
				using (var comHead = Conn.CreateCommand())
				using (var comChildInsert = Conn.CreateCommand())
				using (var comChildUpdate = Conn.CreateCommand())
				using (var comChildDelete = Conn.CreateCommand())
				using (var comDetailInsert = Conn.CreateCommand())
				using (var comDetailUpdate = Conn.CreateCommand())
				using (var comDetailDelete = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comInfo.CommandText = "SELECT a.[Index] as acc_ind, COALESCE(MAX(t.[Index]) + 1, -1) as tran_ind FROM Account a LEFT JOIN [Transaction] t ON a.BankScrapeid = t.AccountBankScrapeid WHERE a.BankScrapeid = @uri GROUP BY a.[Index]";
					comHead.CommandText = "UPDATE BankScrape SET id = @id, website = @website, at = @at, info = @info, externalId = @externalId, ranking = @ranking, tags = @tags WHERE id = @uri";
					comChildInsert.CommandText = "INSERT INTO Account(BankScrapeid, [Index], balance, number, name, notes) VALUES(@id, @index, @balance, @number, @name, @notes)";
					comChildUpdate.CommandText = "UPDATE Account SET balance = @balance, number = @number, name = @name, notes = @notes WHERE BankScrapeid = @id AND [Index] = @index";
					comChildDelete.CommandText = "DELETE FROM Account WHERE BankScrapeid = @id AND [Index] > @index";
					comDetailInsert.CommandText = "INSERT INTO [Transaction](AccountBankScrapeid, AccountIndex, [Index], date, description, currency, amount) VALUES(@id, @acc_index, @index, @date, @description, @currency, @amount)";
					comDetailUpdate.CommandText = "UPDATE [Transaction] SET date = @date, description = @description, currency = @currency, amount = @amount WHERE AccountBankScrapeid = @id AND AccountIndex = @acc_index AND [Index] = @index";
					comDetailDelete.CommandText = "DELETE FROM [Transaction] WHERE AccountBankScrapeid = @id AND AccountIndex = @acc_index AND [Index] > @index";
					comInfo.Transaction = tran;
					comHead.Transaction = tran;
					comChildInsert.Transaction = tran;
					comChildUpdate.Transaction = tran;
					comChildDelete.Transaction = tran;
					comDetailInsert.Transaction = tran;
					comDetailUpdate.Transaction = tran;
					comDetailDelete.Transaction = tran;
					var puri = new SqlParameter("uri", DbType.Int32);
					var phuri = new SqlParameter("uri", DbType.Int32);
					var ph1 = new SqlParameter("id", DbType.Int32);
					var ph2 = new SqlParameter("website", DbType.String);
					var ph3 = new SqlParameter("at", DbType.DateTime);
					var ph4 = new SqlParameter("info", DbType.String);
					var ph5 = new SqlParameter("externalId", DbType.String);
					var ph6 = new SqlParameter("ranking", DbType.Int32);
					var ph7 = new SqlParameter("tags", DbType.String);
					var pci1 = new SqlParameter("id", DbType.Int32);
					var pci2 = new SqlParameter("index", DbType.Int32);
					var pci3 = new SqlParameter("balance", DbType.Decimal);
					var pci4 = new SqlParameter("number", DbType.String);
					var pci5 = new SqlParameter("name", DbType.String);
					var pci6 = new SqlParameter("notes", DbType.String);
					var pcu1 = new SqlParameter("id", DbType.Int32);
					var pcu2 = new SqlParameter("index", DbType.Int32);
					var pcu3 = new SqlParameter("balance", DbType.Decimal);
					var pcu4 = new SqlParameter("number", DbType.String);
					var pcu5 = new SqlParameter("name", DbType.String);
					var pcu6 = new SqlParameter("notes", DbType.String);
					var pcd1 = new SqlParameter("id", DbType.Int32);
					var pcd2 = new SqlParameter("index", DbType.Int32);
					var pdi1 = new SqlParameter("id", DbType.Int32);
					var pdi2 = new SqlParameter("acc_index", DbType.Int32);
					var pdi3 = new SqlParameter("index", DbType.Int32);
					var pdi4 = new SqlParameter("date", DbType.Date);
					var pdi5 = new SqlParameter("description", DbType.String);
					var pdi6 = new SqlParameter("currency", DbType.Object);
					var pdi7 = new SqlParameter("amount", DbType.Decimal);
					var pdu1 = new SqlParameter("id", DbType.Int32);
					var pdu2 = new SqlParameter("acc_index", DbType.Int32);
					var pdu3 = new SqlParameter("index", DbType.Int32);
					var pdu4 = new SqlParameter("date", DbType.Date);
					var pdu5 = new SqlParameter("description", DbType.String);
					var pdu6 = new SqlParameter("currency", DbType.String);
					var pdu7 = new SqlParameter("amount", DbType.Decimal);
					var pdd1 = new SqlParameter("id", DbType.Int32);
					var pdd2 = new SqlParameter("acc_index", DbType.Int32);
					var pdd3 = new SqlParameter("index", DbType.Int32);
					comInfo.Parameters.Add(puri);
					comHead.Parameters.AddRange(new[] { phuri, ph1, ph2, ph3, ph4, ph5, ph6, ph7 });
					comChildInsert.Parameters.AddRange(new[] { pci1, pci2, pci3, pci4, pci5, pci6 });
					comChildUpdate.Parameters.AddRange(new[] { pcu1, pcu2, pcu3, pcu4, pcu5, pcu6 });
					comChildDelete.Parameters.AddRange(new[] { pcd1, pcd2 });
					comDetailInsert.Parameters.AddRange(new[] { pdi1, pdi2, pdi3, pdi4, pdi5, pdi6, pdi7 });
					comDetailUpdate.Parameters.AddRange(new[] { pdu1, pdu2, pdu3, pdu4, pdu5, pdu6, pdu7 });
					comDetailDelete.Parameters.AddRange(new[] { pdd1, pdd2, pdd3 });
					foreach (var item in values)
					{
						var limits = new Dictionary<int, int>();
						puri.Value = item.URI;
						phuri.Value = item.URI;
						using (var dr = comInfo.ExecuteReader())
						{
							while (dr.Read())
								limits.Add(dr.GetInt32(0), dr.GetInt32(1));
						}
						ph1.Value = item.id;
						ph2.Value = item.website.ToString();
						ph3.Value = item.at;
						ph4.Value = Revenj.DatabasePersistence.Postgres.Converters.HstoreConverter.ToDatabase(item.info);
						ph5.Value = (object)item.externalId ?? DBNull.Value;
						ph6.Value = item.ranking;
						ph7.Value = string.Join(",", item.tags);
						comHead.ExecuteNonQuery();
						var min = Math.Min(limits.Count, item.accounts.Count);
						for (int i = 0; i < min; i++)
						{
							var acc = item.accounts[i];
							pcu1.Value = item.id;
							pcu2.Value = i;
							pcu3.Value = acc.balance;
							pcu4.Value = acc.number;
							pcu5.Value = acc.name;
							pcu6.Value = acc.notes;
							comChildUpdate.ExecuteNonQuery();
						}
						for (int i = min; i < item.accounts.Count; i++)
						{
							var acc = item.accounts[i];
							pci1.Value = item.id;
							pci2.Value = i;
							pci3.Value = acc.balance;
							pci4.Value = acc.number;
							pci5.Value = acc.name;
							pci6.Value = acc.notes;
							comChildInsert.ExecuteNonQuery();
						}
						if (limits.Count < item.accounts.Count)
						{
							pcd1.Value = item.id;
							pcd2.Value = limits.Count;
							comChildDelete.ExecuteNonQuery();
						}
						for (int i = 0; i < item.accounts.Count; i++)
						{
							var acc = item.accounts[i];
							min = Math.Min(limits[i], acc.transactions.Count);
							for (int j = 0; j < min; j++)
							{
								var t = acc.transactions[j];
								pdu1.Value = item.id;
								pdu2.Value = i;
								pdu3.Value = j;
								pdu4.Value = t.date;
								pdu5.Value = t.description;
								pdu6.Value = t.currency.ToString();
								pdu7.Value = t.amount;
								comDetailUpdate.ExecuteNonQuery();
							}
							for (int j = min; j < acc.transactions.Count; j++)
							{
								var t = acc.transactions[j];
								pdi1.Value = item.id;
								pdi2.Value = i;
								pdi3.Value = j;
								pdi4.Value = t.date;
								pdi5.Value = t.description;
								pdi6.Value = t.currency.ToString();
								pdi7.Value = t.amount;
								comDetailInsert.ExecuteNonQuery();
							}
							if (limits[i] < acc.transactions.Count)
							{
								pdd1.Value = item.id;
								pdd2.Value = i;
								pdd3.Value = limits[i];
								comDetailDelete.ExecuteNonQuery();
							}

						}
					}
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.id.ToString());
				}
			}

			public void Insert(ComplexRelations.BankScrape item)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comHead.CommandText = "INSERT INTO BankScrape(id, website, at, info, externalId, ranking, tags, createdAt) VALUES(@id, @website, @at, @info, @externalId, @ranking, @tags, @createdAt)";
					comChild.CommandText = "INSERT INTO Account(BankScrapeid, [Index], balance, number, name, notes) VALUES(@id, @index, @balance, @number, @name, @notes)";
					comDetail.CommandText = "INSERT INTO [Transaction](AccountBankScrapeid, AccountIndex, [Index], date, description, currency, amount) VALUES(@id, @acc_index, @index, @date, @description, @currency, @amount)";
					comHead.Transaction = tran;
					comChild.Transaction = tran;
					comDetail.Transaction = tran;
					var ph1 = new SqlParameter("id", DbType.Int32);
					var ph2 = new SqlParameter("website", DbType.String);
					var ph3 = new SqlParameter("at", DbType.DateTime);
					var ph4 = new SqlParameter("info", DbType.String);
					var ph5 = new SqlParameter("externalId", DbType.String);
					var ph6 = new SqlParameter("ranking", DbType.Int32);
					var ph7 = new SqlParameter("tags", DbType.String);
					var ph8 = new SqlParameter("createdAt", DbType.DateTime);
					var pc1 = new SqlParameter("id", DbType.Int32);
					var pc2 = new SqlParameter("index", DbType.Int32);
					var pc3 = new SqlParameter("balance", DbType.Decimal);
					var pc4 = new SqlParameter("number", DbType.String);
					var pc5 = new SqlParameter("name", DbType.String);
					var pc6 = new SqlParameter("notes", DbType.String);
					var pd1 = new SqlParameter("id", DbType.Int32);
					var pd2 = new SqlParameter("acc_index", DbType.Int32);
					var pd3 = new SqlParameter("index", DbType.Int32);
					var pd4 = new SqlParameter("date", DbType.Date);
					var pd5 = new SqlParameter("description", DbType.String);
					var pd6 = new SqlParameter("currency", DbType.String);
					var pd7 = new SqlParameter("amount", DbType.Decimal);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8 });
					comChild.Parameters.AddRange(new[] { pc1, pc2, pc3, pc4, pc5, pc6 });
					comDetail.Parameters.AddRange(new[] { pd1, pd2, pd3, pd4, pd5, pd6, pd7 });
					ph1.Value = item.id;
					ph2.Value = item.website.ToString();
					ph3.Value = item.at;
					ph4.Value = Revenj.DatabasePersistence.Postgres.Converters.HstoreConverter.ToDatabase(item.info);
					ph5.Value = (object)item.externalId ?? DBNull.Value;
					ph6.Value = item.ranking;
					ph7.Value = string.Join(",", item.tags);
					ph8.Value = item.createdAt;
					comHead.ExecuteNonQuery();
					for (int i = 0; i < item.accounts.Count; i++)
					{
						var acc = item.accounts[i];
						pc1.Value = item.id;
						pc2.Value = i;
						pc3.Value = acc.balance;
						pc4.Value = acc.number;
						pc5.Value = acc.name;
						pc6.Value = acc.notes;
						comChild.ExecuteNonQuery();
						for (int j = 0; j < acc.transactions.Count; j++)
						{
							var t = acc.transactions[j];
							pd1.Value = item.id;
							pd2.Value = i;
							pd3.Value = j;
							pd4.Value = t.date;
							pd5.Value = t.description;
							pd6.Value = t.currency.ToString();
							pd7.Value = t.amount;
							comDetail.ExecuteNonQuery();
						}
					}
					tran.Commit();
					ChangeURI.Change(item, item.id.ToString());
				}
			}

			public void Update(ComplexRelations.BankScrape value)
			{
				Update(new[] { value });
			}

			public Report<ComplexRelations.BankScrape> Report(int i)
			{
				var result = new Report<ComplexRelations.BankScrape>();
				var id = i;
				var ids = new[] { i, i + 2, i + 5, i + 7 };
				var start = i;
				var end = i + 6;
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id = @id";
					comHead.Parameters.AddWithValue("id", id);
					comChild.CommandText = "SELECT balance, number, name, notes FROM Account WHERE BankScrapeid = @id ORDER BY [Index]";
					comChild.Parameters.AddWithValue("id", id);
					comDetail.CommandText = "SELECT AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid = @id ORDER BY AccountIndex, [Index]";
					comDetail.Parameters.AddWithValue("id", id);
					result.findOne = ExecuteSingle(comHead, _ => comChild, _ => comDetail);
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id IN (@id1, @id2, @id3, @id4) ORDER BY id";
					comHead.Parameters.Clear();
					comHead.Parameters.AddWithValue("id1", ids[0]);
					comHead.Parameters.AddWithValue("id2", ids[1]);
					comHead.Parameters.AddWithValue("id3", ids[2]);
					comHead.Parameters.AddWithValue("id4", ids[3]);
					comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN (@id1, @id2, @id3, @id4) ORDER BY BankScrapeid, [Index]";
					comChild.Parameters.Clear();
					comChild.Parameters.AddWithValue("id1", ids[0]);
					comChild.Parameters.AddWithValue("id2", ids[1]);
					comChild.Parameters.AddWithValue("id3", ids[2]);
					comChild.Parameters.AddWithValue("id4", ids[3]);
					comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN (@id1, @id2, @id3, @id4) ORDER BY AccountBankScrapeid, AccountIndex, [Index]";
					comDetail.Parameters.Clear();
					comDetail.Parameters.AddWithValue("id1", ids[0]);
					comDetail.Parameters.AddWithValue("id2", ids[1]);
					comDetail.Parameters.AddWithValue("id3", ids[2]);
					comDetail.Parameters.AddWithValue("id4", ids[3]);
					result.findMany = ExecuteCollection(comHead, _ => comChild, _ => comDetail);
					comHead.CommandText = "SELECT TOP 1 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= @after ORDER BY createdAt";
					comHead.Parameters.AddWithValue("after", Now.AddMinutes(i));
					Func<string, SqlCommand> factory1One = pk =>
					{
						comChild.CommandText = "SELECT balance, number, name, notes FROM Account WHERE BankScrapeid = @pk ORDER BY [Index]";
						comChild.Parameters.Clear();
						comChild.Parameters.AddWithValue("pk", int.Parse(pk));
						return comChild;
					};
					Func<string, SqlCommand> factory2One = pk =>
					{
						comDetail.CommandText = "SELECT AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid = @pk ORDER BY AccountIndex, [Index]";
						comDetail.Parameters.Clear();
						comDetail.Parameters.AddWithValue("pk", int.Parse(pk));
						return comDetail;
					};
					result.findFirst = ExecuteSingle(comHead, factory1One, factory2One);
					comHead.CommandText = "SELECT TOP 1 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt <= @before ORDER BY createdAt DESC";
					comHead.Parameters.Clear();
					comHead.Parameters.AddWithValue("before", Now.AddMinutes(i + 10));
					result.findLast = ExecuteSingle(comHead, factory1One, factory2One);
					comHead.CommandText = "SELECT TOP 5 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= @after AND createdAt <= @before ORDER BY createdAt";
					comHead.Parameters.Clear();
					comHead.Parameters.AddWithValue("after", Now.AddMinutes(i));
					comHead.Parameters.AddWithValue("before", Now.AddMinutes(i + 10));
					Func<IEnumerable<string>, SqlCommand> factory1Many = pks =>
					{
						comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN (" + string.Join(",", pks) + ") ORDER BY BankScrapeid, [Index]";
						comChild.Parameters.Clear();
						//TODO: add params as arguments
						return comChild;
					};
					Func<IEnumerable<string>, SqlCommand> factory2Many = pks =>
					{
						comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN (" + string.Join(",", pks) + ") ORDER BY AccountBankScrapeid, AccountIndex, [Index]";
						comDetail.Parameters.Clear();
						return comDetail;
					};
					result.topFive = ExecuteCollection(comHead, factory1Many, factory2Many);
					comHead.CommandText = "SELECT TOP 10 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= @after AND createdAt <= @before ORDER BY createdAt DESC";
					result.lastTen = ExecuteCollection(comHead, factory1Many, factory2Many);
				}
				return result;
			}
		}
	}
}
