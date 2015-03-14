using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using Revenj.DomainPatterns;

namespace Benchmark
{
	class Program
	{
		enum BenchTarget
		{
			Revenj_Postgres, Revenj_Oracle, Npgsql, Revenj_Npgsql, EF_Postgres
		}

		static int Main(string[] args)
		{
			//args = new[] { "Npgsql", "Complex_Relations", "300" };
			//args = new[] { "Revenj_Postgres", "Standard_Objects", "1000" };
			//args = new[] { "EF_Postgres", "Simple", "10000" };
			//args = new[] { "Revenj_Postgres", "Complex_Relations", "300" };
			if (args.Length != 3)
			{
				Console.WriteLine(
					"Expected usage: DALBenchamrk.exe ({0}) ({1}) data",
					string.Join(" | ", Enum.GetNames(typeof(BenchTarget))),
					string.Join(" | ", Enum.GetNames(typeof(BenchType))));
				return 42;
			}
			BenchTarget target;
			if (!Enum.TryParse<BenchTarget>(args[0], out target))
			{
				Console.WriteLine("Unknown target found: " + args[0] + ". Supported targets: " + string.Join(" | ", Enum.GetNames(typeof(BenchTarget))));
				return 5;
			}
			BenchType type;
			if (!Enum.TryParse<BenchType>(args[1], out type))
			{
				Console.WriteLine("Unknown type found: " + args[1] + ". Supported type: " + string.Join(" | ", Enum.GetNames(typeof(BenchType))));
				return 6;
			}
			int data;
			if (!int.TryParse(args[2], out data))
			{
				Console.WriteLine("Invalid data parameter: " + args[2]);
				return 7;
			}
			try
			{
				RunBench(target, type, data);
				return 0;
			}
			catch (NotSupportedException ex)
			{
				Console.Write("bench_supported = -1");
				Console.WriteLine(ex.ToString());
				return -1;
			}
			catch (Exception ex)
			{
				Console.WriteLine("error");
				Console.WriteLine(ex.ToString());
				return -2;
			}
		}

		private static void RunBench(BenchTarget target, BenchType type, int data)
		{
			switch (target)
			{
				case BenchTarget.Npgsql:
					NpgsqlBench.Run(type, data);
					break;
				case BenchTarget.Revenj_Npgsql:
					RevenjNpgsqlBench.Run(type, data);
					break;
				case BenchTarget.Revenj_Oracle:
					RevenjBench.RunOracle(type, data);
					break;
				case BenchTarget.EF_Postgres:
					EntityBench.Run(type, data);
					break;
				default:
					RevenjBench.RunPostgres(type, data);
					break;
			}
		}

		public static void RunBenchmark<T>(
			IBench<T> bench,
			Func<int, T> createNew,
			Action<T, int> changeExisting,
			Func<int, ISpecification<T>> createFilter,
			int data
			)
			where T : IAggregateRoot
		{
			RunBenchmark<T>(
				bench,
				createNew,
				changeExisting,
				createFilter,
				data,
				obj => obj.URI);
		}

		public static void RunBenchmark<T>(
			IBench<T> bench,
			Func<int, T> createNew,
			Action<T, int> changeExisting,
			Func<int, ISpecification<T>> createFilter,
			int data,
			Func<T, string> getURI)
			where T : IAggregateRoot
		{
			for (int i = 0; i < 10; i++)
			{
				bench.Clean();
				var newObject = createNew(i);
				bench.Insert(newObject);
				bench.Analyze();
				var tmp = bench.SearchAll().ToList();
				if (tmp.Count != 1)
					throw new InvalidProgramException("Incorrect results during search all");
				if (!newObject.Equals(tmp[0]))
					throw new InvalidProgramException("Incorrect results when comparing aggregates from search");
				var subset = bench.SearchSubset(i).ToList();
				if (subset.Count != 1)
					throw new InvalidProgramException("Incorrect results during search subset, count=" + subset.Count);
				changeExisting(tmp[0], i);
				bench.Update(tmp);
				changeExisting(tmp[0], i);
				bench.Update(tmp[0]);
				var tq = bench.Query();
				if (tq != null)
				{
					var query = tq.ToList();
					if (query.Count != 1)
						throw new InvalidProgramException("Incorrect results during query");
					if (!tmp[0].Equals(query[0]))
						throw new InvalidProgramException("Incorrect results when comparing aggregates from query");
				}
				var fs = bench.FindSingle(getURI(newObject));
				if (!fs.Equals(tmp[0]))
					throw new InvalidProgramException("Incorrect results when comparing aggregates from find single");
				var fm = bench.FindMany(new[] { getURI(newObject) }).ToList();
				if (fm.Count != 1)
					throw new InvalidProgramException("Incorrect results during find many");
				if (!fm[0].Equals(tmp[0]))
					throw new InvalidProgramException("Incorrect results when comparing aggregates from find many");
				var rep = bench.Report(i);
				if (rep.findMany.Count() != 1 || rep.lastTen.Count() != 1 || rep.topFive.Count() != 1)
					throw new InvalidProgramException("Incorrect results during report");
				if (!rep.findOne.Equals(tmp[0]) || !rep.findFirst.Equals(tmp[0]) || !rep.findLast.Equals(tmp[0])
					|| !rep.findMany.First().Equals(tmp[0]) || !rep.lastTen.First().Equals(tmp[0]) || !rep.topFive.First().Equals(tmp[0]))
					throw new InvalidProgramException("Incorrect results when comparing aggregates from report");
			}
			bench.Clean();
			var items = new List<T>(data);
			for (int i = 0; i < data; i++)
				items.Add(createNew(i));
			var lookupUris = new string[Math.Min(10, Math.Min(data / 2, data / 3 + 10) - data / 3)];
			var sw = Stopwatch.StartNew();
			bench.Insert(items);
			Console.WriteLine("bulk_insert = " + sw.ElapsedMilliseconds);
			for (int i = data / 3; i < data / 3 + lookupUris.Length; i++)
				lookupUris[i - data / 3] = getURI(items[i]);
			for (int i = 0; i < items.Count; i++)
				changeExisting(items[i], i);
			bench.Analyze();
			sw.Restart();
			bench.Update(items);
			Console.WriteLine("bulk_update = " + sw.ElapsedMilliseconds);
			bench.Clean();
			sw.Restart();
			for (int i = 0; i < items.Count / 2; i++)
				bench.Insert(items[i]);
			Console.WriteLine("loop_insert_half = " + sw.ElapsedMilliseconds);
			for (int i = 0; i < items.Count; i++)
				changeExisting(items[i], i);
			bench.Analyze();
			sw.Restart();
			for (int i = 0; i < items.Count / 2; i++)
				bench.Update(items[i]);
			Console.WriteLine("loop_update_half = " + sw.ElapsedMilliseconds);
			bench.Analyze();
			sw.Restart();
			for (int i = 0; i < 100; i++)
			{
				var cnt = bench.SearchAll().Count();
				if (cnt != items.Count / 2)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("search_all = " + sw.ElapsedMilliseconds);
			sw.Restart();
			for (int i = 0; i < 3000; i++)
			{
				var cnt = bench.SearchSubset(i % items.Count / 2).Count();
				if (cnt == 0)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("search_subset = " + sw.ElapsedMilliseconds);
			var q = bench.Query();
			if (q == null)
			{
				Console.WriteLine("query_all = -1");
				Console.WriteLine("query_filter = -1");
			}
			else
			{
				sw.Restart();
				for (int i = 0; i < 100; i++)
				{
					var cnt = bench.Query().ToList().Count;
					if (cnt != items.Count / 2)
						throw new InvalidProgramException("Expecting results");
				}
				Console.WriteLine("query_all = " + sw.ElapsedMilliseconds);
				sw.Restart();
				for (int i = 0; i < 1000; i++)
				{
					var cnt = bench.Query().Where(createFilter(i % items.Count / 2).IsSatisfied).ToList().Count;
					if (cnt == 0)
						throw new InvalidProgramException("Expecting results");
				}
				Console.WriteLine("query_filter = " + sw.ElapsedMilliseconds);
			}
			sw.Restart();
			for (int i = 0; i < 2000; i++)
			{
				var cnt = bench.FindMany(lookupUris).Count();
				if (cnt == 0)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("find_many = " + sw.ElapsedMilliseconds);
			sw.Restart();
			for (int i = 0; i < 5000; i++)
			{
				var res = bench.FindSingle(lookupUris[i % lookupUris.Length]);
				if (res == null)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("find_one = " + sw.ElapsedMilliseconds);
			var r = bench.Report(0);
			if (r == null)
			{
				Console.WriteLine("report = -1");
			}
			else
			{
				sw.Restart();
				for (int i = 0; i < 1000; i++)
				{
					var rr = bench.Report(i % items.Count / 2);
					if (rr.lastTen.Count() == 0 || rr.topFive.Count() == 0 || rr.findMany.Count() == 0
						|| rr.findFirst == null || rr.findLast == null || rr.findOne == null)
						throw new InvalidProgramException("Expecting results");
				}
				Console.WriteLine("report = " + sw.ElapsedMilliseconds);
			}
		}
	}
}