using System;
using System.Collections.Generic;
using System.Configuration;
using System.Linq;
using Revenj.DatabasePersistence.Postgres.Npgsql;
using Revenj.DomainPatterns;
using DALBenchmark;

namespace Benchmark
{
	static class RevenjBench
	{
		private static string ConnectionString = ConfigurationManager.AppSettings["PostgresConnectionString"];
		private static readonly DateTime Now = Factories.Now;
		private static readonly DateTime Today = Factories.Today;

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

		static void Clean(IServiceProvider locator, IDataContext context, string clean)
		{
			context.Delete<Simple.Post>(context.Query<Simple.Post>());
			context.Delete<StandardObjects.Invoice>(context.Query<StandardObjects.Invoice>());
			context.Delete<StandardRelations.Invoice>(context.Query<StandardRelations.Invoice>());
			context.Delete<ComplexObjects.BankScrape>(context.Query<ComplexObjects.BankScrape>());
			context.Delete<ComplexRelations.BankScrape>(context.Query<ComplexRelations.BankScrape>());
		}

		internal static void RunOracle(BenchType type, int data)
		{
			Execute(null, type, data, null);
		}

		internal static void RunPostgres(BenchType type, int data)
		{
			Initialize.Postgres();
			var locator = DSL.Core.SetupPostgres(ConnectionString, true);
			Execute(locator, type, data, null);
		}

		static void Execute(IServiceProvider locator, BenchType type, int data, string clean)
		{
			switch (type)
			{
				case BenchType.Simple:
					Program.RunBenchmark(
						new RunBench<Simple.Post>(
							locator,
							i => new Simple.Post.FindBy(Today.AddDays(i), Today.AddDays(i + 10)),
							GetSimpleReport,
							clean),
						Factories.NewSimple,
						Factories.UpdateSimple,
						i => new Simple.Post.FindBy(Today.AddDays(i), Today.AddDays(i + 10)).IsSatisfied,
						data);
					break;
				case BenchType.Standard_Objects:
					Program.RunBenchmark(
						new RunBench<StandardObjects.Invoice>(
							locator,
							i => new StandardObjects.Invoice.FindBy(i, i + 10),
							GetSOReport,
							clean),
						Factories.NewStandard<StandardObjects.Item>,
						Factories.UpdateStandard,
						i => new StandardObjects.Invoice.FindBy(i, i + 10).IsSatisfied,
						data);
					break;
				case BenchType.Standard_Relations:
					Program.RunBenchmark(
						new RunBench<StandardRelations.Invoice>(
							locator,
							i => new StandardRelations.Invoice.FindBy(i, i + 10),
							GetSRReport,
							clean),
						Factories.NewStandard<StandardRelations.Item>,
						Factories.UpdateStandard,
						i => new StandardRelations.Invoice.FindBy(i, i + 10).IsSatisfied,
						data);
					break;
				case BenchType.Complex_Objects:
					Program.RunBenchmark(
						new RunBench<ComplexObjects.BankScrape>(
							locator,
							i => new ComplexObjects.BankScrape.FindBy(Now.AddMinutes(i), Now.AddMinutes(i + 10)),
							GetCOReport,
							clean),
						Factories.NewComplex<ComplexObjects.Account, ComplexObjects.Transaction>,
						Factories.UpdateComplex,
						i => new ComplexObjects.BankScrape.FindBy(Now.AddMinutes(i), Now.AddMinutes(i + 10)).IsSatisfied,
						data);
					break;
				default:
					Program.RunBenchmark(
						new RunBench<ComplexRelations.BankScrape>(
							locator,
							i => new ComplexRelations.BankScrape.FindBy(Now.AddMinutes(i), Now.AddMinutes(i + 10)),
							GetCRReport,
							clean),
						Factories.NewComplex<ComplexRelations.Account, ComplexRelations.Transaction>,
						Factories.UpdateComplex,
						i => new ComplexRelations.BankScrape.FindBy(Now.AddMinutes(i), Now.AddMinutes(i + 10)).IsSatisfied,
						data);
					break;
			}
		}

		class RunBench<T> : IBench<T>
			where T : IAggregateRoot
		{
			private readonly IServiceProvider Locator;
			private readonly IDataContext Context;
			private readonly IPersistableRepository<T> Repository;
			private readonly Func<int, ISpecification<T>> SearchFilter;
			private readonly Func<int, IServiceProvider, Report<T>> CreateReport;
			private readonly string CleanDb;

			public RunBench(
				IServiceProvider locator,
				Func<int, ISpecification<T>> searchFilter,
				Func<int, IServiceProvider, Report<T>> createReport,
				string clean)
			{
				this.Locator = locator;
				this.SearchFilter = searchFilter;
				this.CreateReport = createReport;
				this.CleanDb = clean;
				Context = locator.Resolve<IDataContext>();
				Repository = locator.Resolve<IPersistableRepository<T>>();
			}

			public void Clean()
			{
				RevenjBench.Clean(Locator, Context, CleanDb);
			}

			public void Analyze()
			{
				RunQuery("ANALYZE");
			}

			public IEnumerable<T> SearchAll()
			{
				return Repository.Search();
			}

			public IEnumerable<T> SearchSubset(int i)
			{
				return Repository.Search(SearchFilter(i), null, null);
			}

			public IQueryable<T> Query()
			{
				return Repository.Query<T>();
			}

			public T FindSingle(string id)
			{
				return Repository.Find(id);
			}

			public IEnumerable<T> FindMany(string[] ids)
			{
				return Repository.Find(ids);
			}

			public void Insert(IEnumerable<T> values)
			{
				Repository.Insert(values);
			}
			//TODO: we could improve performance on persist methods by disabling change tracking before insert/update
			//(it's not used anyway), but this is rarely done in practice, so we wont do it here either
			public void Update(IEnumerable<T> values)
			{
				Repository.Update(values);
			}

			public void Insert(T value)
			{
				Repository.Insert(value);
			}

			public void Update(T value)
			{
				Repository.Update(value);
			}

			public Report<T> Report(int i)
			{
				return CreateReport(i, Locator);
			}
		}

		static Report<Simple.Post> GetSimpleReport(int i, IServiceProvider locator)
		{
			Func<int, Guid> gg = Factories.GetGuid;
			var report = new Simple.FindMultiple
			{
				id = gg(i),
				ids = new[] { gg(i), gg(i + 2), gg(i + 5), gg(i + 7) },
				start = Today.AddDays(i),
				end = Today.AddDays(i + 6)
			};
			var result = report.Populate(locator);
			return new Report<Simple.Post>
			{
				findFirst = result.findFirst,
				findLast = result.findLast,
				findMany = result.findMany,
				findOne = result.findOne,
				topFive = result.topFive,
				lastTen = result.lastTen
			};
		}

		public static Report<StandardObjects.Invoice> GetSOReport(int i, IServiceProvider locator)
		{
			var report = new StandardObjects.FindMultiple
			{
				id = i.ToString(),
				ids = new[] { i.ToString(), (i + 2).ToString(), (i + 5).ToString(), (i + 7).ToString() },
				start = i,
				end = i + 6
			};
			var result = report.Populate(locator);
			return new Report<StandardObjects.Invoice>
			{
				findFirst = result.findFirst,
				findLast = result.findLast,
				findMany = result.findMany,
				findOne = result.findOne,
				topFive = result.topFive,
				lastTen = result.lastTen
			};
		}

		public static Report<StandardRelations.Invoice> GetSRReport(int i, IServiceProvider locator)
		{
			var report = new StandardRelations.FindMultiple
			{
				id = i.ToString(),
				ids = new[] { i.ToString(), (i + 2).ToString(), (i + 5).ToString(), (i + 7).ToString() },
				start = i,
				end = i + 6
			};
			var result = report.Populate(locator);
			return new Report<StandardRelations.Invoice>
			{
				findFirst = result.findFirst,
				findLast = result.findLast,
				findMany = result.findMany,
				findOne = result.findOne,
				topFive = result.topFive,
				lastTen = result.lastTen
			};
		}

		public static Report<ComplexObjects.BankScrape> GetCOReport(int i, IServiceProvider locator)
		{
			var report = new ComplexObjects.FindMultiple
			{
				id = i,
				ids = new[] { i, i + 2, i + 5, i + 7 },
				start = Now.AddMinutes(i),
				end = Now.AddMinutes(i + 6)
			};
			var result = report.Populate(locator);
			return new Report<ComplexObjects.BankScrape>
			{
				findFirst = result.findFirst,
				findLast = result.findLast,
				findMany = result.findMany,
				findOne = result.findOne,
				topFive = result.topFive,
				lastTen = result.lastTen
			};
		}

		public static Report<ComplexRelations.BankScrape> GetCRReport(int i, IServiceProvider locator)
		{
			var report = new ComplexRelations.FindMultiple
			{
				id = i,
				ids = new[] { i, i + 2, i + 5, i + 7 },
				start = Now.AddMinutes(i),
				end = Now.AddMinutes(i + 6)
			};
			var result = report.Populate(locator);
			return new Report<ComplexRelations.BankScrape>
			{
				findFirst = result.findFirst,
				findLast = result.findLast,
				findMany = result.findMany,
				findOne = result.findOne,
				topFive = result.topFive,
				lastTen = result.lastTen
			};
		}
	}
}
