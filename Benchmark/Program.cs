﻿using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Linq.Expressions;
using Revenj.DomainPatterns;

namespace Benchmark
{
	class Program
	{
		enum BenchTarget
		{
			Revenj_Postgres, Revenj_Oracle, Npgsql, Revenj_Npgsql, EF_Postgres, MsSql_AdoNet, Oracle_OdpNet
		}

		static int Main(string[] args)
		{
			//args = new[] { "MsSql_AdoNet", "Standard_Relations", "1000" };
			//args = new[] { "MsSql_AdoNet", "Complex_Relations", "300" };
			//args = new[] { "Revenj_Postgres", "Standard_Relations", "1000" };
			//args = new[] { "Npgsql", "Standard_Relations", "1000" };
			//args = new[] { "Revenj_Postgres", "Standard_Relations", "1000" };
			//args = new[] { "MsSql_AdoNet", "Standard_Relations", "1000" };
			//args = new[] { "EF_Postgres", "Simple", "10000" };
			//args = new[] { "Oracle_OdpNet", "Simple", "10000" };
			//args = new[] { "Oracle_OdpNet", "Standard_Relations", "1000" };
			//args = new[] { "Revenj_Postgres", "Standard_Objects", "1000" };
			//args = new[] { "EF_Postgres", "Standard_Relations", "1000" };
			//args = new[] { "EF_Postgres", "Complex_Relations", "300" };
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
				case BenchTarget.MsSql_AdoNet:
					MsSqlBench.Run(type, data);
					break;
				case BenchTarget.Oracle_OdpNet:
					OracleBench.Run(type, data);
					break;
				default:
					RevenjBench.RunPostgres(type, data);
					break;
			}
		}

		class CaptureGC
		{
			public readonly long Gen0;
			public readonly long Gen1;
			public readonly long Gen2;
			public CaptureGC()
			{
				Gen0 = GC.CollectionCount(0);
				Gen1 = GC.CollectionCount(1);
				Gen2 = GC.CollectionCount(2);
			}
		}

		private static CaptureGC CountGC(CaptureGC last)
		{
			var next = new CaptureGC();
			Console.WriteLine("GC: " + (next.Gen0 - last.Gen0) + " " + (next.Gen1 - last.Gen1) + " " + (next.Gen2 - last.Gen2));
			return next;
		}

		public static void RunBenchmark<T>(
			IBench<T> bench,
			Action<T, int> fillNew,
			Action<T, int> changeExisting,
			Func<int, Expression<Func<T, bool>>> createFilter,
			int data)
			where T : IAggregateRoot, new()// IEquatable<T>, new()
		{
			var gc = new CaptureGC();
			for (int i = 0; i < 50; i++)
			{
				bench.Clean();
				var newObject = new T();
				fillNew(newObject, i);
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
				if (createFilter != null)
				{
					var tq = bench.Query();
					var query = tq.ToList();
					if (query.Count != 1)
						throw new InvalidProgramException("Incorrect results during query");
					if (!tmp[0].Equals(query[0]))
						throw new InvalidProgramException("Incorrect results when comparing aggregates from query");
					var qf = tq.Where(createFilter(i)).ToList();
					if (qf.Count != 1)
						throw new InvalidProgramException("Incorrect results during query filter");
					if (!tmp[0].Equals(qf[0]))
						throw new InvalidProgramException("Incorrect results when comparing aggregates from query filter");
				}
				var fs = bench.FindSingle(newObject.URI);
				if (!fs.Equals(tmp[0]))
					throw new InvalidProgramException("Incorrect results when comparing aggregates from find single");
				var fm = bench.FindMany(new[] { newObject.URI }).ToList();
				if (fm.Count != 1)
					throw new InvalidProgramException("Incorrect results during find many");
				if (!fm[0].Equals(tmp[0]))
					throw new InvalidProgramException("Incorrect results when comparing aggregates from find many");
				var rep = bench.Report(i);
				if (rep != null)
				{
					if (rep.findMany.Count() != 1 || rep.lastTen.Count() != 1 || rep.topFive.Count() != 1)
						throw new InvalidProgramException("Incorrect results during report");
					if (!rep.findOne.Equals(tmp[0]) || !rep.findFirst.Equals(tmp[0]) || !rep.findLast.Equals(tmp[0])
						|| !rep.findMany.First().Equals(tmp[0]) || !rep.lastTen.First().Equals(tmp[0]) || !rep.topFive.First().Equals(tmp[0]))
						throw new InvalidProgramException("Incorrect results when comparing aggregates from report");
				}
			}
			gc = CountGC(gc);
			bench.Clean();
			var items = new List<T>(data);
			for (int i = 0; i < data; i++)
			{
				var t = new T();
				fillNew(t, i);
				items.Add(t);
			}
			var lookupUris = new string[Math.Min(10, Math.Min(data / 2, data / 3 + 10) - data / 3)];
			var uris = new string[data / 2];
			var sw = Stopwatch.StartNew();
			bench.Insert(items);
			Console.WriteLine("bulk_insert = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
			for (int i = 0; i < items.Count; i++)
				changeExisting(items[i], i);
			bench.Analyze();
			sw.Restart();
			bench.Update(items);
			Console.WriteLine("bulk_update = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
			bench.Clean();
			sw.Restart();
			for (int i = 0; i < items.Count / 2; i++)
				bench.Insert(items[i]);
			Console.WriteLine("loop_insert_half = " + sw.ElapsedMilliseconds);
			for (int i = 0; i < items.Count / 2; i++)
				uris[i] = items[i].URI;
			gc = CountGC(gc);
			for (int i = 0; i < items.Count; i++)
				changeExisting(items[i], i);
			bench.Analyze();
			sw.Restart();
			for (int i = 0; i < items.Count / 2; i++)
				bench.Update(items[i]);
			Console.WriteLine("loop_update_half = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
			bench.Analyze();
			sw.Restart();
			for (int i = 0; i < 100; i++)
			{
				var cnt = bench.SearchAll().Count();
				if (cnt != items.Count / 2)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("search_all = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
			sw.Restart();
			for (int i = 0; i < 3000; i++)
			{
				var cnt = bench.SearchSubset(i % items.Count / 2).Count();
				if (cnt == 0)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("search_subset = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
			if (createFilter == null)
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
				gc = CountGC(gc);
				sw.Restart();
				for (int i = 0; i < 1000; i++)
				{
					var cnt = bench.Query().Where(createFilter(i % items.Count / 2)).ToList().Count;
					if (cnt == 0)
						throw new InvalidProgramException("Expecting results");
				}
				Console.WriteLine("query_filter = " + sw.ElapsedMilliseconds);
				gc = CountGC(gc);
			}
			sw.Restart();
			for (int i = 0; i < 2000; i++)
			{
				for (int j = 0; j < lookupUris.Length; j++)
					lookupUris[j] = uris[(i + j + data / 3) % uris.Length];
				var cnt = bench.FindMany(lookupUris).Count();
				if (cnt == 0)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("find_many = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
			sw.Restart();
			for (int i = 0; i < 5000; i++)
			{
				var res = bench.FindSingle(uris[i % uris.Length]);
				if (res == null)
					throw new InvalidProgramException("Expecting results");
			}
			Console.WriteLine("find_one = " + sw.ElapsedMilliseconds);
			gc = CountGC(gc);
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
					var rr = bench.Report(i % data / 2);
					if (rr.lastTen.Count() == 0 || rr.topFive.Count() == 0 || rr.findMany.Count() == 0
						|| rr.findFirst == null || rr.findLast == null || rr.findOne == null)
						throw new InvalidProgramException("Expecting results");
				}
				Console.WriteLine("report = " + sw.ElapsedMilliseconds);
			}
			CountGC(gc);
		}
	}
}