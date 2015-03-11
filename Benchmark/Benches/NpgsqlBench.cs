using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.IO;
using Npgsql;

namespace Benchmark
{
	class NpgsqlBench
	{
		private static string ConnectionString = ConfigurationManager.AppSettings["PostgresConnectionString"];
		private static Stream DbInitScript;

		static NpgsqlBench()
		{
			DbInitScript = typeof(RevenjBench).Assembly.GetManifestResourceStream("DALBenchmark.Database.Postgres.sql");
		}

		static NpgsqlConnection Setup()
		{
			var conn = new NpgsqlConnection(ConnectionString);
			var com = new NpgsqlCommand(new StreamReader(DbInitScript).ReadToEnd()) { Connection = conn };
			conn.Open();
			com.ExecuteNonQuery();
			return conn;
		}

		static void RunQuery(string query)
		{
			using (var conn = new NpgsqlConnection(ConnectionString))
			{
				var com = conn.CreateCommand();
				com.CommandText = query;
				conn.Open();
				com.ExecuteNonQuery();
				conn.Close();
			}
		}

		internal static void Run(BenchType type, int data)
		{
			var conn = Setup();
			switch (type)
			{
				case BenchType.Simple:
					Program.RunBenchmark(
						new SimpleBench(conn),
						Factories.CreateNewSimple,
						Factories.Update,
						Factories.GetSimpleFilter,
						data);
					break;
				case BenchType.Standard_Relations:
					Program.RunBenchmark(
						new StandardBench(conn),
						Factories.CreateSR,
						Factories.Update,
						Factories.GetSRFilter,
						data);
					break;
				case BenchType.Complex_Relations:
					Program.RunBenchmark(
						new ComplexBench(conn),
						Factories.CreateCR,
						Factories.Update,
						Factories.GetCRFilter,
						data);
					break;
				default:
					throw new NotSupportedException("not supported");
			}
		}

		class SimpleBench : IBench<Simple.Post>
		{
			private readonly NpgsqlConnection Conn;
			private readonly DateTime Today = DateTime.Today;

			public SimpleBench(NpgsqlConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM \"Simple\".\"Post\"");
			}

			public void Analyze()
			{
				RunQuery("ANALYZE");
			}

			private static Simple.Post PostFactory(NpgsqlDataReader reader)
			{
				var post = new Simple.Post { id = reader.GetGuid(0), title = reader.GetString(1), created = reader.GetDateTime(2) };
				ChangeURI.Change(post, post.id.ToString());
				return post;
			}

			private static Simple.Post ExecuteSingle(NpgsqlCommand com)
			{
				using (var reader = com.ExecuteReader())
				{
					if (reader.Read())
						return PostFactory(reader);
					return null;
				}
			}

			private static List<Simple.Post> ExecuteCollection(NpgsqlCommand com)
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
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\"";
					return ExecuteCollection(com);
				}
			}

			public IEnumerable<Simple.Post> SearchSubset(int i)
			{
				using (var com = Conn.CreateCommand())
				{
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" p WHERE p.created >= :from AND p.created <= :until";
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
					com.CommandText = "SELECT title, created FROM \"Simple\".\"Post\" WHERE id = '" + id + "'";
					using (var reader = com.ExecuteReader())
					{
						if (reader.Read())
						{
							var post = new Simple.Post { id = Guid.Parse(id), title = reader.GetString(0), created = reader.GetDateTime(1) };
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
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE id IN ('" + string.Join("','", ids) + "')";
					return ExecuteCollection(com);
				}
			}

			public void Insert(IEnumerable<Simple.Post> values)
			{
				using (var com = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					com.CommandText = "INSERT INTO \"Simple\".\"Post\"(id, title, created) VALUES(:id, :title, :created)";
					var p1 = new NpgsqlParameter("id", DbType.Guid);
					var p2 = new NpgsqlParameter("title", DbType.String);
					var p3 = new NpgsqlParameter("created", DbType.Date);
					com.Parameters.AddRange(new[] { p1, p2, p3 });
					foreach (var item in values)
					{
						p1.Value = item.id;
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
					com.CommandText = "UPDATE \"Simple\".\"Post\" SET id = :id, title = :title, created = :created WHERE id = :uri";
					var p1 = new NpgsqlParameter("id", DbType.Guid);
					var p2 = new NpgsqlParameter("title", DbType.String);
					var p3 = new NpgsqlParameter("created", DbType.Date);
					var p4 = new NpgsqlParameter("uri", DbType.Guid);
					com.Parameters.AddRange(new[] { p1, p2, p3, p4 });
					foreach (var item in values)
					{
						p1.Value = item.id;
						p2.Value = item.title;
						p3.Value = item.created;
						p4.Value = Guid.Parse(item.URI);
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
					com.CommandText = "INSERT INTO \"Simple\".\"Post\"(id, title, created) VALUES(:id, :title, :created)";
					com.Parameters.AddWithValue("id", value.id);
					com.Parameters.AddWithValue("title", value.title);
					com.Parameters.AddWithValue("created", value.created);
					com.ExecuteNonQuery();
					ChangeURI.Change(value, value.id.ToString());
				}
			}

			public void Update(Simple.Post value)
			{
				using (var com = Conn.CreateCommand())
				{
					com.CommandText = "UPDATE \"Simple\".\"Post\" SET id = :id, title = :title, created = :created WHERE id = :uri";
					com.Parameters.AddWithValue("id", value.id);
					com.Parameters.AddWithValue("title", value.title);
					com.Parameters.AddWithValue("created", value.created);
					com.Parameters.AddWithValue("uri", Guid.Parse(value.URI));
					com.ExecuteNonQuery();
					ChangeURI.Change(value, value.id.ToString());
				}
			}

			public Report<Simple.Post> Report(int i)
			{
				Func<int, Guid> gg = Factories.GetGuid;
				var result = new Report<Simple.Post>();
				var id = gg(i).ToString();
				var ids = string.Join("','", new[] { gg(i), gg(i + 2), gg(i + 5), gg(i + 7) });
				var start = Today.AddDays(i);
				var end = Today.AddDays(i + 6);
				using (var com = Conn.CreateCommand())
				{
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE id = '" + id + "'";
					result.findOne = ExecuteSingle(com);
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE id IN ('" + ids + "')";
					result.findMany = ExecuteCollection(com);
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created >= '" + start.ToString("yyyy-MM-dd") + "' ORDER BY created ASC LIMIT 1";
					result.findFirst = ExecuteSingle(com);
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created <= '" + end.ToString("yyyy-MM-dd") + "' ORDER BY created DESC LIMIT 1";
					result.findLast = ExecuteSingle(com);
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created >= '" + start.ToString("yyyy-MM-dd") + "' AND created <= '" + end.ToString("yyyy-MM-dd") + "' ORDER BY created ASC LIMIT 5";
					result.topFive = ExecuteCollection(com);
					com.CommandText = "SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created >= '" + start.ToString("yyyy-MM-dd") + "' AND created <= '" + end.ToString("yyyy-MM-dd") + "' ORDER BY created DESC LIMIT 10";
					result.lastTen = ExecuteCollection(com);
				}
				return result;
			}
		}

		class StandardBench : IBench<StandardRelations.Invoice>
		{
			private readonly NpgsqlConnection Conn;

			public StandardBench(NpgsqlConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM \"StandardRelations\".\"Invoice\"");
			}

			public void Analyze()
			{
				RunQuery("ANALYZE");
			}

			private static StandardRelations.Invoice ExecuteSingle(NpgsqlCommand comHead, Func<string, NpgsqlCommand> childFactory)
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
							canceled = readerHead.GetBoolean(4),
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
					using (var childCom = childFactory(invoice.number))
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

			private static StandardRelations.Invoice[] ExecuteCollection(NpgsqlCommand comHead, Func<IEnumerable<string>, NpgsqlCommand> childFactory)
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
					readerHead.Close();
				}
				if (map.Count > 0)
				{
					using (var childCom = childFactory(map.Keys))
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
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" ORDER BY number";
					comChild.CommandText = "SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" ORDER BY \"Invoicenumber\", \"Index\"";
					return ExecuteCollection(comHead, _ => comChild);
				}
			}

			public IEnumerable<StandardRelations.Invoice> SearchSubset(int i)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version >= " + i + " AND version <= " + (i + 10) + " ORDER BY number";
					Func<IEnumerable<string>, NpgsqlCommand> factory = nums =>
					{
						comChild.CommandText = "SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" IN ('" + string.Join("','", nums) + "') ORDER BY \"Invoicenumber\", \"Index\"";
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
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number = '" + id + "'";
					comChild.CommandText = "SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = '" + id + "' ORDER BY \"Index\"";
					return ExecuteSingle(comHead, _ => comChild);
				}
			}

			public IEnumerable<StandardRelations.Invoice> FindMany(string[] ids)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number IN ('" + string.Join("','", ids) + "') ORDER BY number";
					comChild.CommandText = "SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" IN ('" + string.Join("','", ids) + "') ORDER BY \"Invoicenumber\", \"Index\"";
					return ExecuteCollection(comHead, _ => comChild);
				}
			}

			public void Insert(IEnumerable<StandardRelations.Invoice> values)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comHead.CommandText = "INSERT INTO \"StandardRelations\".\"Invoice\"(number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\") VALUES(:number, :dueDate, :total, :paid, :canceled, :version, :tax, :reference, :createdAt, :modifiedAt)";
					comChild.CommandText = "INSERT INTO \"StandardRelations\".\"Item\"(\"Invoicenumber\", \"Index\", product, cost, quantity, \"taxGroup\", discount) VALUES(:number, :index, :product, :cost, :quantity, :taxGroup, :discount)";
					var ph1 = new NpgsqlParameter("number", DbType.String);
					var ph2 = new NpgsqlParameter("dueDate", DbType.Date);
					var ph3 = new NpgsqlParameter("total", DbType.Decimal);
					var ph4 = new NpgsqlParameter("paid", DbType.DateTime);
					var ph5 = new NpgsqlParameter("canceled", DbType.Boolean);
					var ph6 = new NpgsqlParameter("version", DbType.Int64);
					var ph7 = new NpgsqlParameter("tax", DbType.Decimal);
					var ph8 = new NpgsqlParameter("reference", DbType.String);
					var ph9 = new NpgsqlParameter("createdAt", DbType.DateTime);
					var ph10 = new NpgsqlParameter("modifiedAt", DbType.DateTime);
					var pc1 = new NpgsqlParameter("number", DbType.String);
					var pc2 = new NpgsqlParameter("index", DbType.Int32);
					var pc3 = new NpgsqlParameter("product", DbType.String);
					var pc4 = new NpgsqlParameter("cost", DbType.Decimal);
					var pc5 = new NpgsqlParameter("quantity", DbType.Int32);
					var pc6 = new NpgsqlParameter("taxGroup", DbType.Decimal);
					var pc7 = new NpgsqlParameter("discount", DbType.Decimal);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8, ph9, ph10 });
					comChild.Parameters.AddRange(new[] { pc1, pc2, pc3, pc4, pc5, pc6, pc7 });
					foreach (var item in values)
					{
						ph1.Value = item.number;
						ph2.Value = item.dueDate;
						ph3.Value = item.total;
						ph4.Value = item.paid;
						ph5.Value = item.canceled;
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
					comInfo.CommandText = "SELECT COALESCE(MAX(\"Index\"), -1) FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = :uri";
					comHead.CommandText = "UPDATE \"StandardRelations\".\"Invoice\" SET number = :number, \"dueDate\" = :dueDate, total = :total, paid = :paid, canceled = :canceled, version = :version, tax = :tax, reference = :reference, \"modifiedAt\" = :modifiedAt WHERE number = :uri";
					comChildInsert.CommandText = "INSERT INTO \"StandardRelations\".\"Item\"(\"Invoicenumber\", \"Index\", product, cost, quantity, \"taxGroup\", discount) VALUES(:number, :index, :product, :cost, :quantity, :taxGroup, :discount)";
					comChildUpdate.CommandText = "UPDATE \"StandardRelations\".\"Item\" SET product = :product, cost = :cost, quantity = :quantity, \"taxGroup\" = :taxGroup, discount = :discount WHERE \"Invoicenumber\" = :number AND \"Index\" = :index";
					comChildDelete.CommandText = "DELETE FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = :uri AND \"Index\" > :index";
					var puri = new NpgsqlParameter("uri", DbType.String);
					var phuri = new NpgsqlParameter("uri", DbType.String);
					var ph1 = new NpgsqlParameter("number", DbType.String);
					var ph2 = new NpgsqlParameter("dueDate", DbType.Date);
					var ph3 = new NpgsqlParameter("total", DbType.Decimal);
					var ph4 = new NpgsqlParameter("paid", DbType.DateTime);
					var ph5 = new NpgsqlParameter("canceled", DbType.Boolean);
					var ph6 = new NpgsqlParameter("version", DbType.Int64);
					var ph7 = new NpgsqlParameter("tax", DbType.Decimal);
					var ph8 = new NpgsqlParameter("reference", DbType.String);
					var ph9 = new NpgsqlParameter("modifiedAt", DbType.DateTime);
					var pci1 = new NpgsqlParameter("number", DbType.String);
					var pci2 = new NpgsqlParameter("index", DbType.Int32);
					var pci3 = new NpgsqlParameter("product", DbType.String);
					var pci4 = new NpgsqlParameter("cost", DbType.Decimal);
					var pci5 = new NpgsqlParameter("quantity", DbType.Int32);
					var pci6 = new NpgsqlParameter("taxGroup", DbType.Decimal);
					var pci7 = new NpgsqlParameter("discount", DbType.Decimal);
					var pcu1 = new NpgsqlParameter("number", DbType.String);
					var pcu2 = new NpgsqlParameter("index", DbType.Int32);
					var pcu3 = new NpgsqlParameter("product", DbType.String);
					var pcu4 = new NpgsqlParameter("cost", DbType.Decimal);
					var pcu5 = new NpgsqlParameter("quantity", DbType.Int32);
					var pcu6 = new NpgsqlParameter("taxGroup", DbType.Decimal);
					var pcu7 = new NpgsqlParameter("discount", DbType.Decimal);
					var pcd1 = new NpgsqlParameter("number", DbType.String);
					var pcd2 = new NpgsqlParameter("index", DbType.Int32);
					comInfo.Parameters.Add(puri);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8, ph9, phuri });
					comChildInsert.Parameters.AddRange(new[] { pci1, pci2, pci3, pci4, pci5, pci6, pci7 });
					comChildUpdate.Parameters.AddRange(new[] { pcu1, pcu2, pcu3, pcu4, pcu5, pcu6, pcu7 });
					comChildDelete.Parameters.AddRange(new[] { pcd1, pcd2 });
					foreach (var item in values)
					{
						puri.Value = item.URI;
						phuri.Value = item.URI;
						var max = (int)comInfo.ExecuteScalar();
						ph1.Value = item.number;
						ph2.Value = item.dueDate;
						ph3.Value = item.total;
						ph4.Value = item.paid;
						ph5.Value = item.canceled;
						ph6.Value = item.version;
						ph7.Value = item.tax;
						ph8.Value = item.reference;
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

			public void Insert(StandardRelations.Invoice value)
			{
				Insert(new[] { value });
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
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number = '" + id + "'";
					comChild.CommandText = "SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = '" + ids + "' ORDER BY \"Index\"";
					result.findOne = ExecuteSingle(comHead, _ => comChild);
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number IN ('" + string.Join("','", ids) + "') ORDER BY number";
					comChild.CommandText = "SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" IN ('" + string.Join("','", ids) + "') ORDER BY \"Invoicenumber\", \"Index\"";
					result.findMany = ExecuteCollection(comHead, _ => comChild);
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version >= " + start + " ORDER BY \"createdAt\" LIMIT 1";
					Func<string, NpgsqlCommand> factoryOne = n =>
					{
						comChild.CommandText = "SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = '" + n + "' ORDER BY \"Index\"";
						return comChild;
					};
					result.findFirst = ExecuteSingle(comHead, factoryOne);
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version <= " + end + " ORDER BY \"createdAt\" DESC LIMIT 1";
					result.findLast = ExecuteSingle(comHead, factoryOne);
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number IN ('" + string.Join("','", ids) + "') ORDER BY \"createdAt\", number LIMIT 5";
					Func<IEnumerable<string>, NpgsqlCommand> factoryMany = nums =>
					{
						comChild.CommandText = "SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" IN ('" + string.Join("','", nums) + "') ORDER BY \"Invoicenumber\", \"Index\"";
						return comChild;
					};
					result.topFive = ExecuteCollection(comHead, factoryMany);
					comHead.CommandText = "SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number IN ('" + string.Join("','", ids) + "') ORDER BY \"createdAt\" DESC, number LIMIT 10";
					result.lastTen = ExecuteCollection(comHead, factoryMany);
				}
				return result;
			}
		}

		class ComplexBench : IBench<ComplexRelations.BankScrape>
		{
			private readonly NpgsqlConnection Conn;
			private readonly DateTime Now = DateTime.Now;

			public ComplexBench(NpgsqlConnection conn)
			{
				this.Conn = conn;
			}

			public void Clean()
			{
				RunQuery("DELETE FROM \"ComplexRelations\".\"BankScrape\"");
			}

			public void Analyze()
			{
				RunQuery("ANALYZE");
			}

			private static ComplexRelations.BankScrape ExecuteSingle(
				NpgsqlCommand comHead,
				Func<string, NpgsqlCommand> childFactory,
				Func<string, NpgsqlCommand> detailFactory)
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
							tags = new HashSet<string>(readerHead.GetValue(6) as string[]),
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
				NpgsqlCommand comHead,
				Func<IEnumerable<string>, NpgsqlCommand> childFactory,
				Func<IEnumerable<string>, NpgsqlCommand> detailFactory)
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
							tags = new HashSet<string>(readerHead.GetValue(6) as string[]),
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
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" ORDER BY id";
					comChild.CommandText = "SELECT \"BankScrapeid\", balance, number, name, notes FROM \"ComplexRelations\".\"Account\" ORDER BY \"BankScrapeid\", \"Index\"";
					comDetail.CommandText = "SELECT \"AccountBankScrapeid\", \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" ORDER BY \"AccountBankScrapeid\", \"AccountIndex\", \"Index\"";
					return ExecuteCollection(comHead, _ => comChild, _ => comDetail);
				}
			}

			public IEnumerable<ComplexRelations.BankScrape> SearchSubset(int i)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE \"createdAt\" >= '" + Now.AddMinutes(i) + "' AND \"createdAt\" <= '" + Now.AddMinutes(i + 10) + "' ORDER BY id";
					Func<IEnumerable<string>, NpgsqlCommand> factory1 = nums =>
					{
						comChild.CommandText = "SELECT \"BankScrapeid\", balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" IN ('" + string.Join("','", nums) + "') ORDER BY \"BankScrapeid\", \"Index\"";
						return comChild;
					};
					Func<IEnumerable<string>, NpgsqlCommand> factory2 = nums =>
					{
						comDetail.CommandText = "SELECT \"AccountBankScrapeid\", \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" IN ('" + string.Join("','", nums) + "') ORDER BY \"AccountBankScrapeid\", \"AccountIndex\", \"Index\"";
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
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE id = " + id;
					comChild.CommandText = "SELECT balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" = " + id + " ORDER BY \"Index\"";
					comDetail.CommandText = "SELECT \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" = " + id + " ORDER BY \"AccountIndex\", \"Index\"";
					return ExecuteSingle(comHead, _ => comChild, _ => comDetail);
				}
			}

			public IEnumerable<ComplexRelations.BankScrape> FindMany(string[] ids)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE id IN (" + string.Join(",", ids) + ") ORDER BY id";
					comChild.CommandText = "SELECT \"BankScrapeid\", balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" IN (" + string.Join(",", ids) + ") ORDER BY \"BankScrapeid\", \"Index\"";
					comDetail.CommandText = "SELECT \"AccountBankScrapeid\", \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" IN (" + string.Join(",", ids) + ") ORDER BY \"AccountBankScrapeid\", \"AccountIndex\", \"Index\"";
					return ExecuteCollection(comHead, _ => comChild, _ => comDetail);
				}
			}

			public void Insert(IEnumerable<ComplexRelations.BankScrape> values)
			{
				using (var comHead = Conn.CreateCommand())
				using (var comChild = Conn.CreateCommand())
				using (var comDetail = Conn.CreateCommand())
				{
					var tran = Conn.BeginTransaction();
					comHead.CommandText = "INSERT INTO \"ComplexRelations\".\"BankScrape\"(id, website, at, info, \"externalId\", ranking, tags, \"createdAt\") VALUES(:id, :website, :at, cast(:info as hstore), :externalId, :ranking, :tags, :createdAt)";
					comChild.CommandText = "INSERT INTO \"ComplexRelations\".\"Account\"(\"BankScrapeid\", \"Index\", balance, number, name, notes) VALUES(:id, :index, :balance, :number, :name, :notes)";
					comDetail.CommandText = "INSERT INTO \"ComplexRelations\".\"Transaction\"(\"AccountBankScrapeid\", \"AccountIndex\", \"Index\", date, description, currency, amount) VALUES(:id, :acc_index, :index, :date, :description, cast(:currency as \"Complex\".\"Currency\"), :amount)";
					var ph1 = new NpgsqlParameter("id", DbType.Int32);
					var ph2 = new NpgsqlParameter("website", DbType.String);
					var ph3 = new NpgsqlParameter("at", DbType.DateTime);
					var ph4 = new NpgsqlParameter("info", DbType.Object);//TODO: NpgsqlTypes.NpgsqlDbType.Hstore doesn't actually work, so fall back to Revenj conversion
					var ph5 = new NpgsqlParameter("externalId", DbType.String);
					var ph6 = new NpgsqlParameter("ranking", DbType.Int32);
					var ph7 = new NpgsqlParameter("tags", NpgsqlTypes.NpgsqlDbType.Array | NpgsqlTypes.NpgsqlDbType.Varchar);
					var ph8 = new NpgsqlParameter("createdAt", DbType.DateTime);
					var pc1 = new NpgsqlParameter("id", DbType.Int32);
					var pc2 = new NpgsqlParameter("index", DbType.Int32);
					var pc3 = new NpgsqlParameter("balance", DbType.Decimal);
					var pc4 = new NpgsqlParameter("number", DbType.String);
					var pc5 = new NpgsqlParameter("name", DbType.String);
					var pc6 = new NpgsqlParameter("notes", DbType.String);
					var pd1 = new NpgsqlParameter("id", DbType.Int32);
					var pd2 = new NpgsqlParameter("acc_index", DbType.Int32);
					var pd3 = new NpgsqlParameter("index", DbType.Int32);
					var pd4 = new NpgsqlParameter("date", DbType.Date);
					var pd5 = new NpgsqlParameter("description", DbType.String);
					var pd6 = new NpgsqlParameter("currency", DbType.Object);
					var pd7 = new NpgsqlParameter("amount", DbType.Decimal);
					comHead.Parameters.AddRange(new[] { ph1, ph2, ph3, ph4, ph5, ph6, ph7, ph8 });
					comChild.Parameters.AddRange(new[] { pc1, pc2, pc3, pc4, pc5, pc6 });
					comDetail.Parameters.AddRange(new[] { pd1, pd2, pd3, pd4, pd5, pd6, pd7 });
					foreach (var item in values)
					{
						ph1.Value = item.id;
						ph2.Value = item.website.ToString();
						ph3.Value = item.at;
						ph4.Value = Revenj.DatabasePersistence.Postgres.Converters.HstoreConverter.ToDatabase(item.info);
						ph5.Value = item.externalId;
						ph6.Value = item.ranking;
						ph7.Value = item.tags;
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
					}
					tran.Commit();
					foreach (var v in values)
						ChangeURI.Change(v, v.id.ToString());
				}
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
					comInfo.CommandText = "SELECT a.\"Index\" as acc_ind, COALESCE(MAX(t.\"Index\") + 1, -1) as tran_ind FROM \"ComplexRelations\".\"Account\" a LEFT JOIN \"ComplexRelations\".\"Transaction\" t ON a.\"BankScrapeid\" = t.\"AccountBankScrapeid\" WHERE a.\"BankScrapeid\" = :uri GROUP BY a.\"Index\"";
					comHead.CommandText = "UPDATE \"ComplexRelations\".\"BankScrape\" SET id = :id, website = :website, at = :at, info = cast(:info as hstore), \"externalId\" = :externalId, ranking = :ranking, tags = :tags WHERE id = :uri";
					comChildInsert.CommandText = "INSERT INTO \"ComplexRelations\".\"Account\"(\"BankScrapeid\", \"Index\", balance, number, name, notes) VALUES(:id, :index, :balance, :number, :name, :notes)";
					comChildUpdate.CommandText = "UPDATE \"ComplexRelations\".\"Account\" SET balance = :balance, number = :number, name = :name, notes = :notes WHERE \"BankScrapeid\" = :id AND \"Index\" = :index";
					comChildDelete.CommandText = "DELETE FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" = :id AND \"Index\" > :index";
					comDetailInsert.CommandText = "INSERT INTO \"ComplexRelations\".\"Transaction\"(\"AccountBankScrapeid\", \"AccountIndex\", \"Index\", date, description, currency, amount) VALUES(:id, :acc_index, :index, :date, :description, cast(:currency as \"Complex\".\"Currency\"), :amount)";
					comDetailUpdate.CommandText = "UPDATE \"ComplexRelations\".\"Transaction\" SET date = :date, description = :description, currency = cast(:currency as \"Complex\".\"Currency\"), amount = :amount WHERE \"AccountBankScrapeid\" = :id AND \"AccountIndex\" = :acc_index AND \"Index\" = :index";
					comDetailDelete.CommandText = "DELETE FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" = :id AND \"AccountIndex\" = :acc_index AND \"Index\" > :index";
					var puri = new NpgsqlParameter("uri", DbType.Int32);
					var phuri = new NpgsqlParameter("uri", DbType.Int32);
					var ph1 = new NpgsqlParameter("id", DbType.Int32);
					var ph2 = new NpgsqlParameter("website", DbType.String);
					var ph3 = new NpgsqlParameter("at", DbType.DateTime);
					var ph4 = new NpgsqlParameter("info", DbType.Object);//TODO: NpgsqlTypes.NpgsqlDbType.Hstore doesn't actually work, so fall back to Revenj conversion
					var ph5 = new NpgsqlParameter("externalId", DbType.String);
					var ph6 = new NpgsqlParameter("ranking", DbType.Int32);
					var ph7 = new NpgsqlParameter("tags", NpgsqlTypes.NpgsqlDbType.Array | NpgsqlTypes.NpgsqlDbType.Varchar);
					var pci1 = new NpgsqlParameter("id", DbType.Int32);
					var pci2 = new NpgsqlParameter("index", DbType.Int32);
					var pci3 = new NpgsqlParameter("balance", DbType.Decimal);
					var pci4 = new NpgsqlParameter("number", DbType.String);
					var pci5 = new NpgsqlParameter("name", DbType.String);
					var pci6 = new NpgsqlParameter("notes", DbType.String);
					var pcu1 = new NpgsqlParameter("id", DbType.Int32);
					var pcu2 = new NpgsqlParameter("index", DbType.Int32);
					var pcu3 = new NpgsqlParameter("balance", DbType.Decimal);
					var pcu4 = new NpgsqlParameter("number", DbType.String);
					var pcu5 = new NpgsqlParameter("name", DbType.String);
					var pcu6 = new NpgsqlParameter("notes", DbType.String);
					var pcd1 = new NpgsqlParameter("id", DbType.Int32);
					var pcd2 = new NpgsqlParameter("index", DbType.Int32);
					var pdi1 = new NpgsqlParameter("id", DbType.Int32);
					var pdi2 = new NpgsqlParameter("acc_index", DbType.Int32);
					var pdi3 = new NpgsqlParameter("index", DbType.Int32);
					var pdi4 = new NpgsqlParameter("date", DbType.Date);
					var pdi5 = new NpgsqlParameter("description", DbType.String);
					var pdi6 = new NpgsqlParameter("currency", DbType.Object);
					var pdi7 = new NpgsqlParameter("amount", DbType.Decimal);
					var pdu1 = new NpgsqlParameter("id", DbType.Int32);
					var pdu2 = new NpgsqlParameter("acc_index", DbType.Int32);
					var pdu3 = new NpgsqlParameter("index", DbType.Int32);
					var pdu4 = new NpgsqlParameter("date", DbType.Date);
					var pdu5 = new NpgsqlParameter("description", DbType.String);
					var pdu6 = new NpgsqlParameter("currency", DbType.Object);
					var pdu7 = new NpgsqlParameter("amount", DbType.Decimal);
					var pdd1 = new NpgsqlParameter("id", DbType.Int32);
					var pdd2 = new NpgsqlParameter("acc_index", DbType.Int32);
					var pdd3 = new NpgsqlParameter("index", DbType.Int32);
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
						ph5.Value = item.externalId;
						ph6.Value = item.ranking;
						ph7.Value = item.tags;
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

			public void Insert(ComplexRelations.BankScrape value)
			{
				Insert(new[] { value });
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
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE id = " + id;
					comChild.CommandText = "SELECT balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" = " + id + " ORDER BY \"Index\"";
					comDetail.CommandText = "SELECT \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" = " + id + " ORDER BY \"AccountIndex\", \"Index\"";
					result.findOne = ExecuteSingle(comHead, _ => comChild, _ => comDetail);
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE id IN (" + string.Join(",", ids) + ") ORDER BY id";
					comChild.CommandText = "SELECT \"BankScrapeid\", balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" IN (" + string.Join(",", ids) + ") ORDER BY \"BankScrapeid\", \"Index\"";
					comDetail.CommandText = "SELECT \"AccountBankScrapeid\", \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" IN (" + string.Join(",", ids) + ") ORDER BY \"AccountBankScrapeid\", \"AccountIndex\", \"Index\"";
					result.findMany = ExecuteCollection(comHead, _ => comChild, _ => comDetail);
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE \"createdAt\" >= '" + Now.AddMinutes(i) + "' ORDER BY \"createdAt\" LIMIT 1";
					Func<string, NpgsqlCommand> factory1One = pk =>
					{
						comChild.CommandText = "SELECT balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" = " + pk + " ORDER BY \"Index\"";
						return comChild;
					};
					Func<string, NpgsqlCommand> factory2One = pk =>
					{
						comDetail.CommandText = "SELECT \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" = " + pk + " ORDER BY \"AccountIndex\", \"Index\"";
						return comDetail;
					};
					result.findFirst = ExecuteSingle(comHead, factory1One, factory2One);
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE \"createdAt\" <= '" + Now.AddMinutes(i + 10) + "' ORDER BY \"createdAt\" DESC LIMIT 1";
					result.findLast = ExecuteSingle(comHead, factory1One, factory2One);
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE \"createdAt\" >= '" + Now.AddMinutes(i) + "' AND \"createdAt\" <= '" + Now.AddMinutes(i + 10) + "' ORDER BY \"createdAt\" LIMIT 5";
					Func<IEnumerable<string>, NpgsqlCommand> factory1Many = pks =>
					{
						comChild.CommandText = "SELECT \"BankScrapeid\", balance, number, name, notes FROM \"ComplexRelations\".\"Account\" WHERE \"BankScrapeid\" IN (" + string.Join(",", pks) + ") ORDER BY \"BankScrapeid\", \"Index\"";
						return comChild;
					};
					Func<IEnumerable<string>, NpgsqlCommand> factory2Many = pks =>
					{
						comDetail.CommandText = "SELECT \"AccountBankScrapeid\", \"AccountIndex\", date, description, currency, amount FROM \"ComplexRelations\".\"Transaction\" WHERE \"AccountBankScrapeid\" IN (" + string.Join(",", pks) + ") ORDER BY \"AccountBankScrapeid\", \"AccountIndex\", \"Index\"";
						return comDetail;
					};
					result.topFive = ExecuteCollection(comHead, factory1Many, factory2Many);
					comHead.CommandText = "SELECT id, website, at, info, \"externalId\", ranking, tags, \"createdAt\" FROM \"ComplexRelations\".\"BankScrape\" WHERE \"createdAt\" >= '" + Now.AddMinutes(i) + "' AND \"createdAt\" <= '" + Now.AddMinutes(i + 10) + "' ORDER BY \"createdAt\" DESC LIMIT 10";
					result.lastTen = ExecuteCollection(comHead, factory1Many, factory2Many);
				}
				return result;
			}
		}
	}
}
