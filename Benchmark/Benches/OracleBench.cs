using System;
using System.Collections.Generic;
using System.Configuration;
using System.Text;
using Oracle.ManagedDataAccess.Client;

namespace Benchmark
{
	class OracleBench
	{
		private static string ConnectionString = ConfigurationManager.AppSettings["OracleConnectionString"];

		static void RunQuery(string query)
		{
			using (var conn = new OracleConnection(ConnectionString))
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
			var conn = new OracleConnection(ConnectionString);
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
					break;/*
				case BenchType.Complex_Relations:
					Program.RunBenchmark(
						new ComplexBench(conn),
						ComplexBench.NewComplex,
						Factories.UpdateComplex,
						null,
						data);
					break;*/
				default:
					throw new NotSupportedException("not supported");
			}
		}

		class SimpleBench : IBench<Simple.Post>
		{
			private readonly OracleConnection Conn;
			private readonly DateTime Today = Factories.Today;

			public SimpleBench(OracleConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM Post");
			}

			public void Analyze()
			{
				//RunQuery("EXEC dbms_stats.gather_schema_stats('Post');");
			}

			private static Simple.Post PostFactory(OracleDataReader reader)
			{
				var post = new Simple.Post { id = new Guid((byte[])reader.GetValue(0)), title = reader.GetString(1), created = reader.GetDateTime(2) };
				ChangeURI.Change(post, post.id.ToString());
				return post;
			}

			private static Simple.Post ExecuteSingle(OracleCommand com)
			{
				using (var reader = com.ExecuteReader())
				{
					if (reader.Read())
						return PostFactory(reader);
					return null;
				}
			}

			private static List<Simple.Post> ExecuteCollection(OracleCommand com)
			{
				using (var reader = com.ExecuteReader())
				{
					var tmp = new List<Simple.Post>();
					while (reader.Read())
						tmp.Add(PostFactory(reader));
					return tmp;
				}
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
					com.CommandText = "SELECT id, title, created FROM Post p WHERE p.created >= :f AND p.created <= :u";
					com.Parameters.Add("f", Today.AddDays(i));
					com.Parameters.Add("u", Today.AddDays(i + 10));
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
					com.CommandText = "SELECT title, created FROM Post WHERE id = :id";
					var guid = Guid.Parse(id);
					com.Parameters.Add("id", guid.ToByteArray());
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
					var sb = new StringBuilder(60);
					sb.Append("SELECT id, title, created FROM Post WHERE id IN (:id0");
					com.Parameters.Add("id0", Guid.Parse(ids[0]).ToByteArray());
					for (int i = 1; i < ids.Length; i++)
					{
						sb.Append(",:id").Append(i);
						com.Parameters.Add("id" + i, Guid.Parse(ids[i]).ToByteArray());
					}
					sb.Append(")");
					com.CommandText = sb.ToString();
					return ExecuteCollection(com);
				}
			}

			public void Insert(IEnumerable<Simple.Post> values)
			{
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.CommandText = "INSERT INTO Post(id, title, created) VALUES(:id, :title, :created)";
					var p1 = new OracleParameter("id", OracleDbType.Raw);
					var p2 = new OracleParameter("title", OracleDbType.Varchar2);
					var p3 = new OracleParameter("created", OracleDbType.Date);
					com.Parameters.AddRange(new[] { p1, p2, p3 });
					foreach (var item in values)
					{
						p1.Value = item.id.ToByteArray();
						p2.Value = item.title;
						p3.Value = item.created;
						com.ExecuteNonQuery();
					}
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.id.ToString());
				}
			}

			public void Update(IEnumerable<Simple.Post> values)
			{
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.CommandText = "UPDATE Post SET id = :id, title = :title, created = :created WHERE id = :uri";
					var p1 = new OracleParameter("id", OracleDbType.Raw);
					var p2 = new OracleParameter("title", OracleDbType.Varchar2);
					var p3 = new OracleParameter("created", OracleDbType.Date);
					var p4 = new OracleParameter("uri", OracleDbType.Raw);
					com.Parameters.AddRange(new[] { p1, p2, p3, p4 });
					foreach (var item in values)
					{
						p1.Value = item.id.ToByteArray();
						p2.Value = item.title;
						p3.Value = item.created;
						p4.Value = Guid.Parse(item.URI).ToByteArray();
						com.ExecuteNonQuery();
					}
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
					com.CommandText = "INSERT INTO Post(id, title, created) VALUES(:id, :title, :created)";
					com.Parameters.Add("id", value.id.ToByteArray());
					com.Parameters.Add("title", value.title);
					com.Parameters.Add("created", value.created);
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
					com.CommandText = "UPDATE Post SET id = :id, title = :title, created = :created WHERE id = :uri";
					com.Parameters.Add("id", value.id.ToByteArray());
					com.Parameters.Add("title", value.title);
					com.Parameters.Add("created", value.created);
					com.Parameters.Add("uri", Guid.Parse(value.URI).ToByteArray());
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
					//TODO: faster than using refcursors
					com.CommandText = "SELECT id, title, created FROM Post WHERE id = :id";
					com.Parameters.Add("id", id.ToByteArray());
					result.findOne = ExecuteSingle(com);
					com.CommandText = "SELECT id, title, created FROM Post WHERE id IN (:id1, :id2, :id3, :id4)";
					com.Parameters.Clear();
					com.Parameters.Add("id1", ids[0].ToByteArray());
					com.Parameters.Add("id2", ids[1].ToByteArray());
					com.Parameters.Add("id3", ids[2].ToByteArray());
					com.Parameters.Add("id4", ids[3].ToByteArray());
					result.findMany = ExecuteCollection(com);
					com.CommandText = "SELECT id, title, created FROM Post WHERE created >= :s AND RowNum = 1 ORDER BY created ASC";
					com.Parameters.Clear();
					com.Parameters.Add("s", start);
					result.findFirst = ExecuteSingle(com);
					com.CommandText = "SELECT id, title, created FROM Post WHERE created <= :e AND RowNum = 1 ORDER BY created DESC";
					com.Parameters.Clear();
					com.Parameters.Add("e", end);
					result.findLast = ExecuteSingle(com);
					com.CommandText = "SELECT id, title, created FROM Post WHERE created >= :s AND created <= :e AND RowNum < 6 ORDER BY created ASC";
					com.Parameters.Clear();
					com.Parameters.Add("s", start);
					com.Parameters.Add("e", end);
					result.topFive = ExecuteCollection(com);
					com.CommandText = "SELECT id, title, created FROM Post WHERE created >= :s AND created <= :e AND RowNum < 11 ORDER BY created DESC";
					com.Parameters.Clear();
					com.Parameters.Add("s", start);
					com.Parameters.Add("e", end);
					result.lastTen = ExecuteCollection(com);
				}
				return result;
			}
		}

		class StandardBench : IBench<StandardRelations.Invoice>
		{
			private readonly OracleConnection Conn;

			public StandardBench(OracleConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM Invoice");
			}

			public void Analyze()
			{
				//RunQuery("UPDATE STATISTICS Invoice");
				//RunQuery("UPDATE STATISTICS Item");
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

			private static StandardRelations.Invoice ExecuteSingle(OracleCommand comHead, Func<string, OracleCommand> childFactory)
			{
				StandardRelations.Invoice invoice = null;
				using (var readerHead = comHead.ExecuteReader())
				{
					if (readerHead.Read())
					{
						invoice = new StandardRelations.Invoice
						{
							number = readerHead.GetString(0),
							dueDate = readerHead.GetDateTime(1),
							total = readerHead.GetDecimal(2),
							paid = readerHead.IsDBNull(3) ? null : (DateTime?)readerHead.GetDateTime(3),
							canceled = readerHead.GetString(4) == "Y",
							version = readerHead.GetInt64(5),
							tax = readerHead.GetDecimal(6),
							reference = readerHead.IsDBNull(7) ? null : readerHead.GetString(7),
							createdAt = readerHead.GetDateTime(8),
							modifiedAt = readerHead.GetDateTime(9)
						};
						ChangeURI.Change(invoice, invoice.number);
					}
				}
				if (invoice != null)
				{
					var childCom = childFactory(invoice.number);
					using (var readerChild = childCom.ExecuteReader())
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
					}
				}
				return invoice;
			}

			private static StandardRelations.Invoice[] ExecuteCollection(OracleCommand comHead, Func<IEnumerable<string>, OracleCommand> childFactory)
			{
				var map = new Dictionary<string, StandardRelations.Invoice>();
				var order = new Dictionary<string, int>();
				using (var readerHead = comHead.ExecuteReader())
				{
					while (readerHead.Read())
					{
						var number = readerHead.GetString(0);
						var invoice = new StandardRelations.Invoice
						{
							number = number,
							dueDate = readerHead.GetDateTime(1),
							total = readerHead.GetDecimal(2),
							paid = readerHead.IsDBNull(3) ? null : (DateTime?)readerHead.GetDateTime(3),
							canceled = readerHead.GetString(4) == "Y",
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
					readerHead.Close();
				}
				if (map.Count > 0)
				{
					var childCom = childFactory(map.Keys);
					using (var readerChild = childCom.ExecuteReader())
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
					}
				}
				var result = new StandardRelations.Invoice[map.Count];
				foreach (var kv in order)
					result[kv.Value] = map[kv.Key];
				return result;
			}

			public IEnumerable<StandardRelations.Invoice> SearchAll()
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice ORDER BY \"number\"";
					comChild.CommandText = "SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item ORDER BY Invoicenumber, \"Index\"";
					return ExecuteCollection(comHead, _ => comChild);
				}
			}

			public IEnumerable<StandardRelations.Invoice> SearchSubset(int i)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= :s AND version <= :e ORDER BY \"number\"";
					comHead.Parameters.Add("s", i);
					comHead.Parameters.Add("e", i + 10);
					Func<IEnumerable<string>, OracleCommand> factory = nums =>
					{
						//TODO: params
						comChild.CommandText = "SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN ('" + string.Join("','", nums) + "') ORDER BY Invoicenumber, \"Index\"";
						return comChild;
					};
					return ExecuteCollection(comHead, factory);
				}
			}

			public System.Linq.IQueryable<StandardRelations.Invoice> Query()
			{
				return null;
			}

			public StandardRelations.Invoice FindSingle(string id)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE \"number\" = :id";
					comHead.Parameters.Add("id", id);
					comChild.CommandText = "SELECT product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber = :id ORDER BY \"Index\"";
					comChild.Parameters.Add("id", id);
					return ExecuteSingle(comHead, _ => comChild);
				}
			}

			public IEnumerable<StandardRelations.Invoice> FindMany(string[] ids)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE \"number\" IN ('" + string.Join("','", ids) + "') ORDER BY \"number\"";
					comChild.CommandText = "SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN ('" + string.Join("','", ids) + "') ORDER BY Invoicenumber, \"Index\"";
					return ExecuteCollection(comHead, _ => comChild);
				}
			}

			public void Insert(IEnumerable<StandardRelations.Invoice> values)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comHead.CommandText = "INSERT INTO Invoice(\"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt) VALUES(:n, :dueDate, :total, :paid, :canceled, :version, :tax, :r, :createdAt, :modifiedAt)";
					comChild.CommandText = "INSERT INTO Item(Invoicenumber, \"Index\", product, cost, quantity, taxGroup, discount) VALUES(:n, :i, :product, :cost, :quantity, :taxGroup, :discount)";
					var ph1 = new OracleParameter("n", OracleDbType.Varchar2);
					var ph2 = new OracleParameter("dueDate", OracleDbType.Date);
					var ph3 = new OracleParameter("total", OracleDbType.Decimal);
					var ph4 = new OracleParameter("paid", OracleDbType.TimeStampTZ);
					var ph5 = new OracleParameter("canceled", OracleDbType.Varchar2);
					var ph6 = new OracleParameter("version", OracleDbType.Int64);
					var ph7 = new OracleParameter("tax", OracleDbType.Decimal);
					var ph8 = new OracleParameter("r", OracleDbType.Varchar2);
					var ph9 = new OracleParameter("createdAt", OracleDbType.TimeStampTZ);
					var ph10 = new OracleParameter("modifiedAt", OracleDbType.TimeStampTZ);
					var pc1 = new OracleParameter("n", OracleDbType.Varchar2);
					var pc2 = new OracleParameter("i", OracleDbType.Int32);
					var pc3 = new OracleParameter("product", OracleDbType.Varchar2);
					var pc4 = new OracleParameter("cost", OracleDbType.Decimal);
					var pc5 = new OracleParameter("quantity", OracleDbType.Int32);
					var pc6 = new OracleParameter("taxGroup", OracleDbType.Decimal);
					var pc7 = new OracleParameter("discount", OracleDbType.Decimal);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8, ph9, ph10 });
					comChild.Parameters.AddRange(new[] { pc1, pc2, pc3, pc4, pc5, pc6, pc7 });
					foreach (var item in values)
					{
						ph1.Value = item.number;
						ph2.Value = item.dueDate;
						ph3.Value = item.total;
						ph4.Value = item.paid;
						ph5.Value = item.canceled ? "Y" : "N";
						ph6.Value = item.version;
						ph7.Value = item.tax;
						ph8.Value = item.reference;
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
					}
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.number);
				}
			}

			public void Update(IEnumerable<StandardRelations.Invoice> values)
			{
				using (var comInfo = Conn.CreateCommand())
				using (var comHead = Conn.CreateCommand())
				using (var comChildInsert = Conn.CreateCommand())
				using (var comChildUpdate = Conn.CreateCommand())
				using (var comChildDelete = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comInfo.CommandText = "SELECT COALESCE(MAX(\"Index\"), -1) FROM Item WHERE Invoicenumber = :uri";
					comHead.CommandText = "UPDATE Invoice SET \"number\" = :n, dueDate = :dueDate, total = :total, paid = :paid, canceled = :canceled, version = :version, tax = :tax, reference = :r, modifiedAt = :modifiedAt WHERE \"number\" = :uri";
					comChildInsert.CommandText = "INSERT INTO Item(Invoicenumber, \"Index\", product, cost, quantity, taxGroup, discount) VALUES(:n, :i, :product, :cost, :quantity, :taxGroup, :discount)";
					comChildUpdate.CommandText = "UPDATE Item SET product = :product, cost = :cost, quantity = :quantity, taxGroup = :taxGroup, discount = :discount WHERE Invoicenumber = :n AND \"Index\" = :i";
					comChildDelete.CommandText = "DELETE FROM Item WHERE Invoicenumber = :uri AND \"Index\" > :i";
					comInfo.Transaction = tran;
					comHead.Transaction = tran;
					comChildInsert.Transaction = tran;
					comChildUpdate.Transaction = tran;
					comChildDelete.Transaction = tran;
					var puri = new OracleParameter("uri", OracleDbType.Varchar2);
					var phuri = new OracleParameter("uri", OracleDbType.Varchar2);
					var ph1 = new OracleParameter("n", OracleDbType.Varchar2);
					var ph2 = new OracleParameter("dueDate", OracleDbType.Date);
					var ph3 = new OracleParameter("total", OracleDbType.Decimal);
					var ph4 = new OracleParameter("paid", OracleDbType.TimeStampTZ);
					var ph5 = new OracleParameter("canceled", OracleDbType.Varchar2);
					var ph6 = new OracleParameter("version", OracleDbType.Int64);
					var ph7 = new OracleParameter("tax", OracleDbType.Decimal);
					var ph8 = new OracleParameter("r", OracleDbType.Varchar2);
					var ph9 = new OracleParameter("modifiedAt", OracleDbType.TimeStampTZ);
					var pci1 = new OracleParameter("number", OracleDbType.Varchar2);
					var pci2 = new OracleParameter("i", OracleDbType.Int32);
					var pci3 = new OracleParameter("product", OracleDbType.Varchar2);
					var pci4 = new OracleParameter("cost", OracleDbType.Decimal);
					var pci5 = new OracleParameter("quantity", OracleDbType.Int32);
					var pci6 = new OracleParameter("taxGroup", OracleDbType.Decimal);
					var pci7 = new OracleParameter("discount", OracleDbType.Decimal);
					var pcu1 = new OracleParameter("n", OracleDbType.Varchar2);
					var pcu2 = new OracleParameter("i", OracleDbType.Int32);
					var pcu3 = new OracleParameter("product", OracleDbType.Varchar2);
					var pcu4 = new OracleParameter("cost", OracleDbType.Decimal);
					var pcu5 = new OracleParameter("quantity", OracleDbType.Int32);
					var pcu6 = new OracleParameter("taxGroup", OracleDbType.Decimal);
					var pcu7 = new OracleParameter("discount", OracleDbType.Decimal);
					var pcd1 = new OracleParameter("n", OracleDbType.Varchar2);
					var pcd2 = new OracleParameter("i", OracleDbType.Int32);
					comInfo.Parameters.Add(puri);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8, ph9, phuri });
					comChildInsert.Parameters.AddRange(new[] { pci1, pci2, pci3, pci4, pci5, pci6, pci7 });
					comChildUpdate.Parameters.AddRange(new[] { pcu3, pcu4, pcu5, pcu6, pcu7, pcu1, pcu2 });
					comChildDelete.Parameters.AddRange(new[] { pcd1, pcd2 });
					foreach (var item in values)
					{
						puri.Value = item.URI;
						phuri.Value = item.URI;
						var max = (int)(decimal)comInfo.ExecuteScalar();
						ph1.Value = item.number;
						ph2.Value = item.dueDate;
						ph3.Value = item.total;
						ph4.Value = (object)item.paid ?? DBNull.Value;
						ph5.Value = item.canceled ? "Y" : "N";
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
					}
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.number);
				}
			}

			public void Insert(StandardRelations.Invoice item)
			{
				Insert(new[] { item });
			}

			public void Update(StandardRelations.Invoice value)
			{
				Update(new[] { value });
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
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE \"number\" = :id";
					comHead.Parameters.Add("id", id);
					comChild.CommandText = "SELECT product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber = :id ORDER BY \"Index\"";
					comChild.Parameters.Add("id", id);
					result.findOne = ExecuteSingle(comHead, _ => comChild);
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE \"number\" IN (:id1, :id2, :id3, :id4) ORDER BY \"number\"";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("id1", ids[0]);
					comHead.Parameters.Add("id2", ids[1]);
					comHead.Parameters.Add("id3", ids[2]);
					comHead.Parameters.Add("id4", ids[3]);
					comChild.CommandText = "SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN (:id1, :id2, :id3, :id4) ORDER BY Invoicenumber, \"Index\"";
					comChild.Parameters.Clear();
					comChild.Parameters.Add("id1", ids[0]);
					comChild.Parameters.Add("id2", ids[1]);
					comChild.Parameters.Add("id3", ids[2]);
					comChild.Parameters.Add("id4", ids[3]);
					result.findMany = ExecuteCollection(comHead, _ => comChild);
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= :s AND RowNum = 1 ORDER BY createdAt";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("s", start);
					Func<string, OracleCommand> factoryOne = n =>
					{
						comChild.CommandText = "SELECT product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber = :id ORDER BY \"Index\"";
						comChild.Parameters.Clear();
						comChild.Parameters.Add("id", n);
						return comChild;
					};
					result.findFirst = ExecuteSingle(comHead, factoryOne);
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version <= :e AND RowNum = 1 ORDER BY createdAt DESC";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("e", end);
					result.findLast = ExecuteSingle(comHead, factoryOne);
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= :s AND version <= :e AND RowNum < 6 ORDER BY createdAt, \"number\"";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("s", start);
					comHead.Parameters.Add("e", end);
					Func<IEnumerable<string>, OracleCommand> factoryMany = nums =>
					{
						comChild.CommandText = "SELECT Invoicenumber, product, cost, quantity, taxGroup, discount FROM Item WHERE Invoicenumber IN ('" + string.Join("','", nums) + "') ORDER BY Invoicenumber, \"Index\"";
						return comChild;
					};
					result.topFive = ExecuteCollection(comHead, factoryMany);
					comHead.CommandText = "SELECT \"number\", dueDate, total, paid, canceled, version, tax, reference, createdAt, modifiedAt FROM Invoice WHERE version >= :s AND version <= :e AND RowNum < 11 ORDER BY createdAt DESC, \"number\"";
					result.lastTen = ExecuteCollection(comHead, factoryMany);
				}
				return result;
			}
		}
		/*
		class ComplexBench : IBench<ComplexRelations.BankScrape>
		{
			private readonly OracleConnection Conn;
			private readonly DateTime Now = Factories.Now;

			public ComplexBench(OracleConnection conn)
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
				OracleCommand comHead,
				Func<string, OracleCommand> childFactory,
				Func<string, OracleCommand> detailFactory)
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
							var acc = scrape.accounts\"Index\";
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
				OracleCommand comHead,
				Func<IEnumerable<string>, OracleCommand> childFactory,
				Func<IEnumerable<string>, OracleCommand> detailFactory)
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
							var tran = accounts\"Index\".transactions;
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
					comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account ORDER BY BankScrapeid, \"Index\"";
					comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] ORDER BY AccountBankScrapeid, AccountIndex, \"Index\"";
					return ExecuteCollection(comHead, _ => comChild, _ => comDetail);
				}
			}

			public IEnumerable<ComplexRelations.BankScrape> SearchSubset(int i)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= :after AND createdAt <= :before ORDER BY id";
					comHead.Parameters.Add("after", Now.AddMinutes(i));
					comHead.Parameters.Add("before", Now.AddMinutes(i + 10));
					Func<IEnumerable<string>, OracleCommand> factory1 = nums =>
					{
						comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN ('" + string.Join("','", nums) + "') ORDER BY BankScrapeid, \"Index\"";
						return comChild;
					};
					Func<IEnumerable<string>, OracleCommand> factory2 = nums =>
					{
						comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN ('" + string.Join("','", nums) + "') ORDER BY AccountBankScrapeid, AccountIndex, \"Index\"";
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
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id = :id";
					comHead.Parameters.Add("id", pk);
					comChild.CommandText = "SELECT balance, number, name, notes FROM Account WHERE BankScrapeid = :id ORDER BY \"Index\"";
					comChild.Parameters.Add("id", pk);
					comDetail.CommandText = "SELECT AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid = :id ORDER BY AccountIndex, \"Index\"";
					comDetail.Parameters.Add("id", pk);
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
					comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN (" + string.Join(",", ids) + ") ORDER BY BankScrapeid, \"Index\"";
					comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN (" + string.Join(",", ids) + ") ORDER BY AccountBankScrapeid, AccountIndex, \"Index\"";
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
					comInfo.CommandText = "SELECT a.\"Index\" as acc_ind, COALESCE(MAX(t.\"Index\") + 1, -1) as tran_ind FROM Account a LEFT JOIN [Transaction] t ON a.BankScrapeid = t.AccountBankScrapeid WHERE a.BankScrapeid = :uri GROUP BY a.\"Index\"";
					comHead.CommandText = "UPDATE BankScrape SET id = :id, website = :website, at = :at, info = :info, externalId = :externalId, ranking = :ranking, tags = :tags WHERE id = :uri";
					comChildInsert.CommandText = "INSERT INTO Account(BankScrapeid, \"Index\", balance, number, name, notes) VALUES(:id, :index, :balance, :number, :name, :notes)";
					comChildUpdate.CommandText = "UPDATE Account SET balance = :balance, number = :number, name = :name, notes = :notes WHERE BankScrapeid = :id AND \"Index\" = :index";
					comChildDelete.CommandText = "DELETE FROM Account WHERE BankScrapeid = :id AND \"Index\" > :index";
					comDetailInsert.CommandText = "INSERT INTO [Transaction](AccountBankScrapeid, AccountIndex, \"Index\", date, description, currency, amount) VALUES(:id, :acc_index, :index, :date, :description, :currency, :amount)";
					comDetailUpdate.CommandText = "UPDATE [Transaction] SET date = :date, description = :description, currency = :currency, amount = :amount WHERE AccountBankScrapeid = :id AND AccountIndex = :acc_index AND \"Index\" = :index";
					comDetailDelete.CommandText = "DELETE FROM [Transaction] WHERE AccountBankScrapeid = :id AND AccountIndex = :acc_index AND \"Index\" > :index";
					comInfo.Transaction = tran;
					comHead.Transaction = tran;
					comChildInsert.Transaction = tran;
					comChildUpdate.Transaction = tran;
					comChildDelete.Transaction = tran;
					comDetailInsert.Transaction = tran;
					comDetailUpdate.Transaction = tran;
					comDetailDelete.Transaction = tran;
					var puri = new OracleParameter("uri", DbType.Int32);
					var phuri = new OracleParameter("uri", DbType.Int32);
					var ph1 = new OracleParameter("id", DbType.Int32);
					var ph2 = new OracleParameter("website", DbType.String);
					var ph3 = new OracleParameter("at", DbType.DateTime);
					var ph4 = new OracleParameter("info", DbType.String);
					var ph5 = new OracleParameter("externalId", DbType.String);
					var ph6 = new OracleParameter("ranking", DbType.Int32);
					var ph7 = new OracleParameter("tags", DbType.String);
					var pci1 = new OracleParameter("id", DbType.Int32);
					var pci2 = new OracleParameter("index", DbType.Int32);
					var pci3 = new OracleParameter("balance", DbType.Decimal);
					var pci4 = new OracleParameter("number", DbType.String);
					var pci5 = new OracleParameter("name", DbType.String);
					var pci6 = new OracleParameter("notes", DbType.String);
					var pcu1 = new OracleParameter("id", DbType.Int32);
					var pcu2 = new OracleParameter("index", DbType.Int32);
					var pcu3 = new OracleParameter("balance", DbType.Decimal);
					var pcu4 = new OracleParameter("number", DbType.String);
					var pcu5 = new OracleParameter("name", DbType.String);
					var pcu6 = new OracleParameter("notes", DbType.String);
					var pcd1 = new OracleParameter("id", DbType.Int32);
					var pcd2 = new OracleParameter("index", DbType.Int32);
					var pdi1 = new OracleParameter("id", DbType.Int32);
					var pdi2 = new OracleParameter("acc_index", DbType.Int32);
					var pdi3 = new OracleParameter("index", DbType.Int32);
					var pdi4 = new OracleParameter("date", DbType.Date);
					var pdi5 = new OracleParameter("description", DbType.String);
					var pdi6 = new OracleParameter("currency", DbType.Object);
					var pdi7 = new OracleParameter("amount", DbType.Decimal);
					var pdu1 = new OracleParameter("id", DbType.Int32);
					var pdu2 = new OracleParameter("acc_index", DbType.Int32);
					var pdu3 = new OracleParameter("index", DbType.Int32);
					var pdu4 = new OracleParameter("date", DbType.Date);
					var pdu5 = new OracleParameter("description", DbType.String);
					var pdu6 = new OracleParameter("currency", DbType.String);
					var pdu7 = new OracleParameter("amount", DbType.Decimal);
					var pdd1 = new OracleParameter("id", DbType.Int32);
					var pdd2 = new OracleParameter("acc_index", DbType.Int32);
					var pdd3 = new OracleParameter("index", DbType.Int32);
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
					comHead.CommandText = "INSERT INTO BankScrape(id, website, at, info, externalId, ranking, tags, createdAt) VALUES(:id, :website, :at, :info, :externalId, :ranking, :tags, :createdAt)";
					comChild.CommandText = "INSERT INTO Account(BankScrapeid, \"Index\", balance, number, name, notes) VALUES(:id, :index, :balance, :number, :name, :notes)";
					comDetail.CommandText = "INSERT INTO [Transaction](AccountBankScrapeid, AccountIndex, \"Index\", date, description, currency, amount) VALUES(:id, :acc_index, :index, :date, :description, :currency, :amount)";
					comHead.Transaction = tran;
					comChild.Transaction = tran;
					comDetail.Transaction = tran;
					var ph1 = new OracleParameter("id", DbType.Int32);
					var ph2 = new OracleParameter("website", DbType.String);
					var ph3 = new OracleParameter("at", DbType.DateTime);
					var ph4 = new OracleParameter("info", DbType.String);
					var ph5 = new OracleParameter("externalId", DbType.String);
					var ph6 = new OracleParameter("ranking", DbType.Int32);
					var ph7 = new OracleParameter("tags", DbType.String);
					var ph8 = new OracleParameter("createdAt", DbType.DateTime);
					var pc1 = new OracleParameter("id", DbType.Int32);
					var pc2 = new OracleParameter("index", DbType.Int32);
					var pc3 = new OracleParameter("balance", DbType.Decimal);
					var pc4 = new OracleParameter("number", DbType.String);
					var pc5 = new OracleParameter("name", DbType.String);
					var pc6 = new OracleParameter("notes", DbType.String);
					var pd1 = new OracleParameter("id", DbType.Int32);
					var pd2 = new OracleParameter("acc_index", DbType.Int32);
					var pd3 = new OracleParameter("index", DbType.Int32);
					var pd4 = new OracleParameter("date", DbType.Date);
					var pd5 = new OracleParameter("description", DbType.String);
					var pd6 = new OracleParameter("currency", DbType.String);
					var pd7 = new OracleParameter("amount", DbType.Decimal);
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
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id = :id";
					comHead.Parameters.Add("id", id);
					comChild.CommandText = "SELECT balance, number, name, notes FROM Account WHERE BankScrapeid = :id ORDER BY \"Index\"";
					comChild.Parameters.Add("id", id);
					comDetail.CommandText = "SELECT AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid = :id ORDER BY AccountIndex, \"Index\"";
					comDetail.Parameters.Add("id", id);
					result.findOne = ExecuteSingle(comHead, _ => comChild, _ => comDetail);
					comHead.CommandText = "SELECT id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE id IN (:id1, :id2, :id3, :id4) ORDER BY id";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("id1", ids[0]);
					comHead.Parameters.Add("id2", ids[1]);
					comHead.Parameters.Add("id3", ids[2]);
					comHead.Parameters.Add("id4", ids[3]);
					comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN (:id1, :id2, :id3, :id4) ORDER BY BankScrapeid, \"Index\"";
					comChild.Parameters.Clear();
					comChild.Parameters.Add("id1", ids[0]);
					comChild.Parameters.Add("id2", ids[1]);
					comChild.Parameters.Add("id3", ids[2]);
					comChild.Parameters.Add("id4", ids[3]);
					comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN (:id1, :id2, :id3, :id4) ORDER BY AccountBankScrapeid, AccountIndex, \"Index\"";
					comDetail.Parameters.Clear();
					comDetail.Parameters.Add("id1", ids[0]);
					comDetail.Parameters.Add("id2", ids[1]);
					comDetail.Parameters.Add("id3", ids[2]);
					comDetail.Parameters.Add("id4", ids[3]);
					result.findMany = ExecuteCollection(comHead, _ => comChild, _ => comDetail);
					comHead.CommandText = "SELECT TOP 1 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= :after ORDER BY createdAt";
					comHead.Parameters.Add("after", Now.AddMinutes(i));
					Func<string, OracleCommand> factory1One = pk =>
					{
						comChild.CommandText = "SELECT balance, number, name, notes FROM Account WHERE BankScrapeid = :pk ORDER BY \"Index\"";
						comChild.Parameters.Clear();
						comChild.Parameters.Add("pk", int.Parse(pk));
						return comChild;
					};
					Func<string, OracleCommand> factory2One = pk =>
					{
						comDetail.CommandText = "SELECT AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid = :pk ORDER BY AccountIndex, \"Index\"";
						comDetail.Parameters.Clear();
						comDetail.Parameters.Add("pk", int.Parse(pk));
						return comDetail;
					};
					result.findFirst = ExecuteSingle(comHead, factory1One, factory2One);
					comHead.CommandText = "SELECT TOP 1 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt <= :before ORDER BY createdAt DESC";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("before", Now.AddMinutes(i + 10));
					result.findLast = ExecuteSingle(comHead, factory1One, factory2One);
					comHead.CommandText = "SELECT TOP 5 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= :after AND createdAt <= :before ORDER BY createdAt";
					comHead.Parameters.Clear();
					comHead.Parameters.Add("after", Now.AddMinutes(i));
					comHead.Parameters.Add("before", Now.AddMinutes(i + 10));
					Func<IEnumerable<string>, OracleCommand> factory1Many = pks =>
					{
						comChild.CommandText = "SELECT BankScrapeid, balance, number, name, notes FROM Account WHERE BankScrapeid IN (" + string.Join(",", pks) + ") ORDER BY BankScrapeid, \"Index\"";
						comChild.Parameters.Clear();
						//TODO: add params as arguments
						return comChild;
					};
					Func<IEnumerable<string>, OracleCommand> factory2Many = pks =>
					{
						comDetail.CommandText = "SELECT AccountBankScrapeid, AccountIndex, date, description, currency, amount FROM [Transaction] WHERE AccountBankScrapeid IN (" + string.Join(",", pks) + ") ORDER BY AccountBankScrapeid, AccountIndex, \"Index\"";
						comDetail.Parameters.Clear();
						return comDetail;
					};
					result.topFive = ExecuteCollection(comHead, factory1Many, factory2Many);
					comHead.CommandText = "SELECT TOP 10 id, website, at, info, externalId, ranking, tags, createdAt FROM BankScrape WHERE createdAt >= :after AND createdAt <= :before ORDER BY createdAt DESC";
					result.lastTen = ExecuteCollection(comHead, factory1Many, factory2Many);
				}
				return result;
			}
		}*/
	}
}
