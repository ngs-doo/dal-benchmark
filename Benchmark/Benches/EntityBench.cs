using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Data.Objects.DataClasses;
using System.Linq;
using ComplexRelations;
using DALBenchmark;
using Revenj.DomainPatterns;
using StandardRelations;

namespace Benchmark
{
	class EntityBench
	{
		static EntityBench()
		{
		}

		internal static void Run(BenchType type, int data)
		{
			var context = new EfContext();

			switch (type)
			{
				case BenchType.Simple:
					Program.RunBenchmark(
						new SimpleEntityBench(Factories.Now, Factories.Today),
						Factories.CreateNewSimple,
						Factories.Update,
						Factories.GetSimpleFilter,
						data,
						obj => obj.id.ToString());
					break;
				case BenchType.Standard_Relations:
					Program.RunBenchmark<Invoice>(
						new StandardEntityBench(Factories.Now, Factories.Today),
						Factories.CreateSR,
						Factories.Update,
						Factories.GetSRFilter,
						data,
						obj => obj.number);
					break;
				case BenchType.Complex_Relations:
					// TODO handle non-scalar properties
					Program.RunBenchmark(
						new ComplexRelationsEntityBench(Factories.Now, Factories.Today),
						Factories.CreateCR,
						Factories.Update,
						Factories.GetCRFilter,
						data,
						obj => obj.id.ToString());
					break;
				default:
					throw new NotSupportedException("not supported");
			}
		}

		public partial class BenchEntities : DbContext
		{
			public BenchEntities()
				: base("name=EfContext")
			{
			}

			protected override void OnModelCreating(DbModelBuilder modelBuilder)
			{
			}

			public virtual DbSet<EfPost> Posts { get; set; }
			public virtual DbSet<EfInvoice> Invoices { get; set; }
			public virtual DbSet<EfBankScrape> BankScrapes { get; set; }
		}


		class SimpleEntityBench : BaseEntityBench<EfPost, Simple.Post>, IBench<Simple.Post>
		{
			public static DateTime Now;
			public static DateTime Today;

			public void Clean()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"Simple\".\"Post\"");
				}
			}

			public SimpleEntityBench(DateTime now, DateTime today)
			{
				Now = now;
				Today = today;
				var start = Today;
				var end = Today.AddDays(10);
				GetDbSet = (ctx) => ctx.Posts;
				OrderField = it => it.created;
			}

			public override Simple.Post CastEntityToAggregate(EfPost post)
			{
				return new Simple.Post
				{
					created = post.created,
					id = post.id,
					title = post.title
				};
			}

			public override EfPost CastAggregateToEntity(Simple.Post post)
			{
				return new EfPost
				{
					created = post.created,
					id = post.id,
					title = post.title
				};
			}

			public override IEnumerable<Simple.Post> FindMany(string[] ids)
			{
				var guids = ids.Select(it => new Guid(it));
				return FindManyWith(it => guids.Contains(it.id));
			}

			public IQueryable<Simple.Post> Query()
			{
				var ctx = GetContext();
				var result = GetDbSet(ctx).Select<EfPost, Simple.Post>(
					it => new Simple.Post
					{
						id = it.id,
						created = it.created,
						title = it.title
					}
					);
				return result;
			}

			public override IQueryable<EfPost> FindById(string id)
			{
				return GetDbSet(GetContext())
					.Where(it => it.id == new Guid(id));
			}

			public IEnumerable<Simple.Post> SearchSubset(int i)
			{
				var start = Today.AddDays(i);
				var end = Today.AddDays(i + 10);
				return SearchSubset(it => it.created >= start, it => it.created <= end);
			}

			public Report<Simple.Post> Report(int i)
			{
				Func<int, Guid> gg = Factories.GetGuid;
				var id = gg(i).ToString();
				string[] ids = new[] { gg(i), gg(i + 2), gg(i + 5), gg(i + 7) }
					.Select(it => it.ToString()).ToArray();
				var start = Today.AddDays(i);
				var end = Today.AddDays(i + 6);
				return Report(id, ids, it => it.created >= start, it => it.created <= end);
			}
		}


		class StandardEntityBench : BaseEntityBench<EfInvoice, Invoice>, IBench<Invoice>
		{
			public static DateTime Now;
			public static DateTime Today;

			public StandardEntityBench(DateTime now, DateTime today)
			{
				Now = now;
				Today = today;
				GetDbSet = (ctx) => ctx.Invoices;
				OrderField = it => it.createdAt.DateTime;
			}

			public void Clean()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"StandardRelations\".\"Invoice\" CASCADE");
				}
			}

			public override Invoice CastEntityToAggregate(EfInvoice it)
			{
				return new Invoice
				{
					items = it.Item.Select<EfItem, Item>(
						a => new Item
						{
							cost = a.cost,
							discount = a.discount,
							product = a.product,
							quantity = a.quantity,
							taxGroup = a.taxGroup
						}
					).ToList(),
					canceled = it.canceled,
					createdAt = it.createdAt.DateTime,
					dueDate = it.dueDate,
					modifiedAt = it.modifiedAt.DateTime,
					number = it.number,
					paid = it.paid.GetValueOrDefault().DateTime,
					reference = it.reference,
					tax = it.tax,
					total = it.total,
					version = it.version
				};
			}

			public override EfInvoice CastAggregateToEntity(Invoice invoice)
			{
				var result = new EfInvoice
				{
					canceled = invoice.canceled,
					createdAt = invoice.createdAt,
					dueDate = invoice.dueDate,
					modifiedAt = invoice.modifiedAt,
					number = invoice.number,
					paid = invoice.paid,
					reference = invoice.reference,
					tax = invoice.tax,
					total = invoice.total,
					version = invoice.version,
				};
				for (int i = 0; i < invoice.items.Count; i++)
				{
					var it = invoice.items[i];
					result.Item.Add(new EfItem
					{
						cost = it.cost,
						discount = it.discount,
						Index = i,
						Invoicenumber = invoice.number,
						product = it.product,
						quantity = it.quantity,
						taxGroup = it.taxGroup
					});
				}
				return result;
			}

			public override IEnumerable<Invoice> FindMany(string[] ids)
			{
				return FindManyWith(it => ids.Contains(it.number));
			}

			public IQueryable<Invoice> Query()
			{
				var ctx = GetContext();
				var result = GetDbSet(ctx).Select<EfInvoice, Invoice>(
					it => new Invoice
					{
						items = it.Item.Select<EfItem, Item>(
							a => new Item
							{
								cost = a.cost,
								discount = a.discount,
								product = a.product,
								quantity = a.quantity,
								taxGroup = a.taxGroup
							}
						).ToList(),
						canceled = it.canceled,
						// TODO
						//createdAt = DbFunctions.TruncateTime(it.createdAt.DateTime).Value,
						dueDate = it.dueDate,
						//modifiedAt = DbFunctions.TruncateTime(it.modifiedAt.DateTime).Value,
						number = it.number,
						//paid = DbFunctions.TruncateTime(it.paid.Value.DateTime),
						reference = it.reference,
						tax = it.tax,
						total = it.total,
						version = it.version
					}
					);
				return result;
			}

			public override IQueryable<EfInvoice> FindById(string id)
			{
				return GetDbSet(GetContext())
					.Where(it => it.number == id);
			}

			public IEnumerable<Invoice> SearchSubset(int i)
			{
				return SearchSubset(it => it.version >= i, it => it.version <= i);
			}

			public Report<Invoice> Report(int i)
			{
				var id = i.ToString();
				var ids = new[] { i.ToString(), (i + 2).ToString(), (i + 5).ToString(), (i + 7).ToString() };
				var start = i;
				var end = i + 6;
				return Report(id, ids, it => it.version >= start, it => it.version <= end);
			}
		}


		class ComplexRelationsEntityBench : BaseEntityBench<EfBankScrape, BankScrape>, IBench<BankScrape>
		{
			public static DateTime Now;
			public static DateTime Today;

			public ComplexRelationsEntityBench(DateTime now, DateTime today)
			{
				Now = now;
				Today = today;
				GetDbSet = (ctx) => ctx.BankScrapes;
				OrderField = it => it.createdAt.DateTime;
			}

			public void Clean()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"ComplexRelations\".\"BankScrape\" CASCADE");
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"ComplexRelations\".\"Account\" CASCADE");
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"ComplexRelations\".\"Transaction\" CASCADE");
				}
			}

			public override BankScrape CastEntityToAggregate(EfBankScrape it)
			{
				return new BankScrape
				{
					accounts = it.Account.Select(
						a => new Account
						{
							balance = a.balance,
							BankScrapeid = a.BankScrapeid,
							Index = a.Index,
							name = a.name,
							notes = a.notes,
							number = a.number,
							transactions = a.Transaction.Select(
								t => new Transaction
								{
									AccountBankScrapeid = t.AccountBankScrapeid,
									AccountIndex = t.AccountIndex,
									amount = t.amount,
									// currency = t.
									date = t.date,
									description = t.description,
									Index = t.Index,
								}
							).ToList()
						}
					).ToList(),
					at = it.at.DateTime,
					createdAt = it.createdAt.DateTime,
					externalId = it.externalId,
					id = it.id,
					// TODO complex types
					// info = it.info,
					// tags = it.tags,
					ranking = it.ranking,
					website = new Uri(it.website)
				};
			}

			public override EfBankScrape CastAggregateToEntity(BankScrape it)
			{
				var res = new EfBankScrape
				{
					at = it.at,
					createdAt = it.createdAt,
					externalId = it.externalId,
					id = it.id,
					// TODO complex types
					// info = it.info,
					// tags = it.tags,
					ranking = it.ranking,
					website = it.website.ToString()
				};
				int accountIndex = 0;
				int transactionIndex = 0;
				foreach (var a in it.accounts)
				{

					var acc = new EfAccount
					{
						balance = a.balance,
						BankScrapeid = it.id,//a.BankScrapeid,
						//Index = a.Index,
						Index = accountIndex,
						name = a.name,
						notes = a.notes,
						number = a.number,
					};
					accountIndex++;
					foreach (var t in a.transactions)
					{
						acc.Transaction.Add(
							new EfTransaction
							{
								AccountBankScrapeid = acc.BankScrapeid, //.AccountBankScrapeid,
								AccountIndex = acc.Index,//t.AccountIndex,
								amount = t.amount,
								date = t.date,
								description = t.description,
								//Index = t.Index,
								Index = transactionIndex,
							}
						);
						transactionIndex++;
					}
					res.Account.Add(acc);
				}
				return res;
			}

			public override IEnumerable<BankScrape> FindMany(string[] ids)
			{
				var keys = ids.Cast<int>();
				return FindManyWith(it => true);//keys.Contains(it.id));
			}

			public IQueryable<BankScrape> Query()
			{
				// TODO
				return null;
			}

			public override IQueryable<EfBankScrape> FindById(string id)
			{
				try
				{
					int intId = Int32.Parse(id);
					return GetDbSet(GetContext())
						.Where(it => it.id == intId);
				}
				catch (Exception)
				{
					//System.Console.WriteLine("Id = " + id);
					throw;
				}
			}

			public IEnumerable<BankScrape> SearchSubset(int i)
			{
				var start = Now.AddMinutes(i - 1);
				var end = Now.AddMinutes(i + 10);
				return SearchSubset(it => it.createdAt >= start, it => it.createdAt <= end);
			}

			public Report<BankScrape> Report(int i)
			{
				var id = i.ToString();
				var ids = new[] { i, i + 2, i + 5, i + 7 }.Select(it => it.ToString()).ToArray();
				var start = Now.AddMinutes(i - 1);
				var end = Now.AddMinutes(i + 6);
				return Report(id, ids, it => it.createdAt >= start, it => it.createdAt <= end);
			}

			public new void Update(IEnumerable<BankScrape> values)
			{
				var ctx = GetContext();
				foreach (var root in values)
				{
					var efItem = CastAggregateToEntity(root);
					//System.Console.WriteLine("id = " + efItem.id);
					ctx.Entry(efItem).State = EntityState.Modified;
				}
				ctx.SaveChanges();
				DisposeContext(ctx);
			}
		}


		abstract class BaseEntityBench<TEnt, TRoot>
			where TEnt : EntityObject
			where TRoot : IAggregateRoot
		{
			protected bool ShouldDisposeContext = true;

			protected Func<BenchEntities, DbSet<TEnt>> GetDbSet;
			protected Func<TEnt, DateTime> OrderField;

			private static byte[] GuidBytes = new byte[8];

			public BaseEntityBench() { }

			public abstract IQueryable<TEnt> FindById(string id);

			public abstract TRoot CastEntityToAggregate(TEnt entity);

			public abstract TEnt CastAggregateToEntity(TRoot root);

			public static Guid GetGuid(int i)
			{
				return new Guid(i, (short)i, (byte)i, GuidBytes);
			}

			public TRoot FindSingle(string id)
			{
				var ctx = GetContext();
				var result = FindById(id).FirstOrDefault();
				DisposeContext(ctx);
				return result != null
					? CastEntityToAggregate(result)
					: default(TRoot);
			}

			protected BenchEntities GetContext()
			{
				return new BenchEntities();
			}

			protected void DisposeContext(DbContext context)
			{
				if (ShouldDisposeContext)
					context.Dispose();
			}

			public void Analyze()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("ANALYZE");
				}
			}

			public IEnumerable<TRoot> SearchAll()
			{
				var ctx = GetContext();
				var result = GetDbSet(ctx).ToList().Select(CastEntityToAggregate)
					.ToList();
				DisposeContext(ctx);
				return result;
			}

			public IEnumerable<TRoot> SearchSubset(
				Func<TEnt, bool> from,
				Func<TEnt, bool> until)
			{
				var ctx = GetContext();
				var db = GetDbSet(ctx);
				var result = db
					.Where(from)
					.Where(until)
					.Select(CastEntityToAggregate)
					.ToList();
				DisposeContext(ctx);
				return result;
			}

			public IEnumerable<TRoot> FindManyWith(Func<TEnt, bool> filter)
			{
				var ctx = GetContext();
				var result = GetDbSet(ctx).Where(filter)
					.Select(CastEntityToAggregate)
					.ToList();
				DisposeContext(ctx);
				return result;
			}

			public void Insert(IEnumerable<TRoot> values)
			{
				var ctx = GetContext();
				GetDbSet(ctx).AddRange(values.Select(CastAggregateToEntity));
				ctx.SaveChanges();
				DisposeContext(ctx);
			}

			public void Update(IEnumerable<TRoot> values)
			{
				var ctx = GetContext();
				foreach (var root in values)
					ctx.Entry(CastAggregateToEntity(root)).State = EntityState.Modified;
				ctx.SaveChanges();
				DisposeContext(ctx);
			}

			public void Insert(TRoot value)
			{
				var ctx = GetContext();
				GetDbSet(ctx).Add(CastAggregateToEntity(value));
				ctx.SaveChanges();
				DisposeContext(ctx);
			}

			public abstract IEnumerable<TRoot> FindMany(string[] ids);

			public void Update(TRoot value)
			{
				var ctx = GetContext();
				var item = CastAggregateToEntity(value);
				ctx.Entry(item).State = EntityState.Modified;
				ctx.SaveChanges();
				DisposeContext(ctx);
			}

			public Report<TRoot> Report(
				string id,
				string[] ids,
				Func<TEnt, bool> from,
				Func<TEnt, bool> until)
			{
				var ctx = GetContext();

				var report = new Report<TRoot>();
				report.findOne = FindSingle(id.ToString());
				report.findMany = FindMany(ids.Select(it => it.ToString()).ToArray());
				report.findFirst = GetDbSet(GetContext())
					.Where(from)
					.OrderBy(OrderField)
					.Select<TEnt, TRoot>(it => CastEntityToAggregate(it))
					.FirstOrDefault();
				report.findLast = GetDbSet(GetContext())
					.Where(until)
					.OrderByDescending(OrderField)
					.Select<TEnt, TRoot>(it => CastEntityToAggregate(it))
					.FirstOrDefault();
				report.topFive = GetDbSet(GetContext())
					.Where(from)
					.Where(until)
					.OrderBy(OrderField)
					.Select<TEnt, TRoot>(it => CastEntityToAggregate(it))
					.Take(5);
				report.lastTen = GetDbSet(GetContext())
					.Where(until)
					.OrderByDescending(OrderField)
					.Select<TEnt, TRoot>(it => CastEntityToAggregate(it))
					.Take(10);

				DisposeContext(ctx);
				return report;
			}
		}
	}
}