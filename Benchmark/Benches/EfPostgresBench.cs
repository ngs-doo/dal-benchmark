using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Data.Entity.Infrastructure;
using System.Data.Objects.DataClasses;
using System.Linq;
using System.Linq.Expressions;
using DALBenchmark;
using Revenj.DomainPatterns;

namespace Benchmark
{
	static class EntityBench
	{
		private static readonly DateTime Now = Factories.Now;
		private static readonly DateTime Today = Factories.Today;

		internal static void Run(BenchType type, int data)
		{
			Initialize.Postgres();
			switch (type)
			{
				case BenchType.Simple:
					Program.RunBenchmark<EfPost>(
						new SimpleEntityBench(),
						Factories.NewSimple,
						Factories.UpdateSimple,
						SimpleEntityBench.Filter,
						data);
					break;
				case BenchType.Standard_Relations:
					Program.RunBenchmark<EfInvoice>(
						new StandardEntityBench(),
						StandardEntityBench.NewStandard,
						Factories.UpdateStandard,
						StandardEntityBench.Filter,
						data);
					break;
				case BenchType.Complex_Relations:
					// TODO handle non-scalar properties
					Program.RunBenchmark<EfBankScrape>(
						new ComplexRelationsEntityBench(),
						ComplexRelationsEntityBench.NewComplex,
						Factories.UpdateComplex,
						ComplexRelationsEntityBench.Filter,
						data);
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
				this.Configuration.LazyLoadingEnabled = false;
				this.Configuration.ProxyCreationEnabled = false;
				this.Configuration.AutoDetectChangesEnabled = false;
			}

			protected override void OnModelCreating(DbModelBuilder modelBuilder)
			{
			}

			public virtual DbSet<EfPost> Posts { get; set; }
			public virtual DbSet<EfInvoice> Invoices { get; set; }
			public virtual DbSet<EfBankScrape> BankScrapes { get; set; }
		}

		class SimpleEntityBench : BaseEntityBench<EfPost>, IBench<EfPost>
		{
			public void Clean()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"Simple\".\"Post\"");
				}
			}

			public SimpleEntityBench()
				: base(ctx => ctx.Posts, ctx => ctx.Posts)
			{
			}

			public override Expression<Func<EfPost, bool>> FindById(string ids)
			{
				var guid = new Guid(ids);
				return it => it.id == guid;
			}

			public override Expression<Func<EfPost, bool>> FindByIds(string[] ids)
			{
				var guids = ids.Select(it => new Guid(it)).ToList();
				return it => guids.Contains(it.id);
			}

			public static Expression<Func<EfPost, bool>> Filter(int i)
			{
				var start = Today.AddDays(i);
				var end = Today.AddDays(i + 10);
				return it => it.created >= start && it.created <= end;
			}

			public override Expression<Func<EfPost, bool>> SubsetFilter(int i)
			{
				return Filter(i);
			}

			public Report<EfPost> Report(int i)
			{
				Func<int, Guid> gg = Factories.GetGuid;
				var id = gg(i);
				var ids = new[] { gg(i), gg(i + 2), gg(i + 5), gg(i + 7) };
				var start = Today.AddDays(i);
				var end = Today.AddDays(i + 6);
				var dbSet = GetDbSet(SharedContext);
				var report = new Report<EfPost>();
				report.findOne = dbSet.Where(it => it.id == id).OrderBy(it => it.created).FirstOrDefault();
				report.findMany = dbSet.Where(it => ids.Contains(it.id)).OrderBy(it => it.created).ToList();
				report.findFirst = dbSet.Where(it => it.created >= start).OrderBy(it => it.created).FirstOrDefault();
				report.findLast = dbSet.Where(it => it.created <= end).OrderByDescending(it => it.created).FirstOrDefault();
				report.topFive = dbSet.Where(it => it.created >= start && it.created <= end).OrderBy(it => it.created).Take(5).ToList();
				report.lastTen = dbSet.Where(it => it.created >= start && it.created <= end).OrderByDescending(it => it.created).Take(10).ToList();
				return report;
			}
		}

		class StandardEntityBench : BaseEntityBench<EfInvoice>, IBench<EfInvoice>
		{
			public StandardEntityBench()
				: base(ctx => ctx.Invoices, ctx => ctx.Invoices.Include("Item"))
			{
			}

			public void Clean()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"StandardRelations\".\"Invoice\" CASCADE");
				}
			}

			public static void NewStandard(EfInvoice inv, int i)
			{
				Factories.NewStandard<EfItem>(inv, i);
				int cnt = 0;
				foreach (var it in inv.items)
				{
					it.Index = cnt++;
					it.Invoicenumber = inv.number;
				}
			}

			public override Expression<Func<EfInvoice, bool>> FindById(string id)
			{
				return it => it.number == id;
			}

			public override Expression<Func<EfInvoice, bool>> FindByIds(string[] ids)
			{
				return it => ids.Contains(it.number);
			}

			public static Expression<Func<EfInvoice, bool>> Filter(int i)
			{
				return it => it.version >= i && it.version <= i;
			}

			public override Expression<Func<EfInvoice, bool>> SubsetFilter(int i)
			{
				return Filter(i);
			}

			public Report<EfInvoice> Report(int i)
			{
				var id = i.ToString();
				var ids = new[] { i.ToString(), (i + 2).ToString(), (i + 5).ToString(), (i + 7).ToString() };
				var start = i;
				var end = i + 6;
				var dbSet = GetDbSet(SharedContext);
				var report = new Report<EfInvoice>();
				report.findOne = dbSet.Where(it => it.number == id).OrderBy(it => it.createdAt).FirstOrDefault();
				report.findMany = dbSet.Where(it => ids.Contains(it.number)).OrderBy(it => it.createdAt).ToList();
				report.findFirst = dbSet.Where(it => it.version >= start).OrderBy(it => it.createdAt).FirstOrDefault();
				report.findLast = dbSet.Where(it => it.version <= end).OrderByDescending(it => it.createdAt).FirstOrDefault();
				report.topFive = dbSet.Where(it => it.version >= start && it.version <= end).OrderBy(it => it.createdAt).Take(5).ToList();
				report.lastTen = dbSet.Where(it => it.version >= start && it.version <= end).OrderByDescending(it => it.createdAt).Take(10).ToList();
				return report;
			}
		}

		class ComplexRelationsEntityBench : BaseEntityBench<EfBankScrape>, IBench<EfBankScrape>
		{
			public ComplexRelationsEntityBench()
				: base(ctx => ctx.BankScrapes, ctx => ctx.BankScrapes.Include("Account.Transaction"))
			{
			}

			public void Clean()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("TRUNCATE TABLE \"ComplexRelations\".\"BankScrape\" CASCADE");
				}
			}

			public static void NewComplex(EfBankScrape scrape, int i)
			{
				Factories.NewComplex<EfAccount, EfTransaction>(scrape, i);
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

			public override Expression<Func<EfBankScrape, bool>> FindById(string id)
			{
				var key = int.Parse(id);
				return it => it.id == key;
			}

			public override Expression<Func<EfBankScrape, bool>> FindByIds(string[] ids)
			{
				var keys = ids.Select(it => int.Parse(it)).ToList();
				return it => keys.Contains(it.id);
			}

			public static Expression<Func<EfBankScrape, bool>> Filter(int i)
			{
				var start = Now.AddMinutes(i);
				var end = Now.AddMinutes(i + 10);
				return it => it.createdAt >= start && it.createdAt <= end;
			}

			public override Expression<Func<EfBankScrape, bool>> SubsetFilter(int i)
			{
				return Filter(i);
			}

			public Report<EfBankScrape> Report(int i)
			{
				var ids = new[] { i, i + 2, i + 5, i + 7 };
				var start = Now.AddMinutes(i);
				var end = Now.AddMinutes(i + 6);
				var dbSet = GetDbSet(SharedContext);
				var report = new Report<EfBankScrape>();
				report.findOne = dbSet.Where(it => it.id == i).OrderBy(it => it.createdAt).FirstOrDefault();
				report.findMany = dbSet.Where(it => ids.Contains(it.id)).OrderBy(it => it.createdAt).ToList();
				report.findFirst = dbSet.Where(it => it.createdAt >= start).OrderBy(it => it.createdAt).FirstOrDefault();
				report.findLast = dbSet.Where(it => it.createdAt <= end).OrderByDescending(it => it.createdAt).FirstOrDefault();
				report.topFive = dbSet.Where(it => it.createdAt >= start && it.createdAt <= end).OrderBy(it => it.createdAt).Take(5).ToList();
				report.lastTen = dbSet.Where(it => it.createdAt >= start && it.createdAt <= end).OrderByDescending(it => it.createdAt).Take(10).ToList();
				return report;
			}
		}

		abstract class BaseEntityBench<TEnt>
			where TEnt : EntityObject, IAggregateRoot, IEquatable<TEnt>
		{
			protected readonly Func<BenchEntities, DbSet<TEnt>> GetDbSet;
			protected readonly DbQuery<TEnt> DbQuery;

			protected readonly BenchEntities SharedContext = new BenchEntities();

			public BaseEntityBench(
				Func<BenchEntities, DbSet<TEnt>> getDbSet,
				Func<BenchEntities, DbQuery<TEnt>> getDbQuery)
			{
				this.GetDbSet = getDbSet;
				//Disable tracking so objects are not read from cache, but rematerialized every time
				this.DbQuery = getDbQuery(SharedContext).AsNoTracking();
			}

			public abstract Expression<Func<TEnt, bool>> FindById(string id);
			public abstract Expression<Func<TEnt, bool>> FindByIds(string[] id);
			public abstract Expression<Func<TEnt, bool>> SubsetFilter(int i);

			public TEnt FindSingle(string id)
			{
				//ISSUE: Find can't be used since it doesn't support include or cant be used without tracking
				return DbQuery.Where(FindById(id)).FirstOrDefault();
			}

			public IEnumerable<TEnt> FindMany(string[] id)
			{
				return DbQuery.Where(FindByIds(id)).ToList();
			}

			protected BenchEntities GetContext()
			{
				return new BenchEntities();
			}

			public void Analyze()
			{
				using (var ctx = new BenchEntities())
				{
					ctx.Database.ExecuteSqlCommand("ANALYZE");
				}
			}

			public IQueryable<TEnt> Query()
			{
				return DbQuery;
			}

			public IEnumerable<TEnt> SearchAll()
			{
				return DbQuery.ToList();
			}

			public IEnumerable<TEnt> SearchSubset(int i)
			{
				return DbQuery.Where(SubsetFilter(i)).ToList();
			}

			public void Insert(IEnumerable<TEnt> values)
			{
				var ctx = GetContext();
				GetDbSet(ctx).AddRange(values);
				ctx.SaveChanges();
				ctx.Dispose();
			}

			public void Update(IEnumerable<TEnt> values)
			{
				var ctx = GetContext();
				foreach (var root in values)
					ctx.Entry(root).State = EntityState.Modified;
				ctx.SaveChanges();
				ctx.Dispose();
			}

			public void Insert(TEnt value)
			{
				var ctx = GetContext();
				GetDbSet(ctx).Add(value);
				ctx.SaveChanges();
				ctx.Dispose();
			}

			public void Update(TEnt value)
			{
				var ctx = GetContext();
				ctx.Entry(value).State = EntityState.Modified;
				ctx.SaveChanges();
				ctx.Dispose();
			}
		}
	}
}

namespace DALBenchmark
{
	partial class EfPost : IAggregateRoot, IEquatable<EfPost>
	{
		public bool Equals(EfPost other)
		{
			return true;//TODO
		}

		public bool Equals(IEntity other)
		{
			var ef = other as EfPost;
			return ef != null && ef.id == this.id;
		}

		public string URI
		{
			get { return this.id.ToString(); }
		}
	}
	partial class EfInvoice : IAggregateRoot, IEquatable<EfInvoice>
	{
		public bool Equals(EfInvoice other)
		{
			return true;//TODO
		}

		public bool Equals(IEntity other)
		{
			var ef = other as EfInvoice;
			return ef != null && ef.number == this.number;
		}

		public string URI
		{
			get { return this.number; }
		}
		public EntityCollection<EfItem> items { get { return Item; } }
	}
	partial class EfBankScrape : IAggregateRoot, IEquatable<EfBankScrape>
	{
		public bool Equals(EfBankScrape other)
		{
			return true;//TODO
		}

		public bool Equals(IEntity other)
		{
			var ef = other as EfBankScrape;
			return ef != null && ef.id == this.id;
		}

		public string URI
		{
			get { return this.id.ToString(); }
		}
		public EntityCollection<EfAccount> accounts { get { return Account; } }
	}
	partial class EfAccount
	{
		public EntityCollection<EfTransaction> transactions { get { return Transaction; } }
	}
}