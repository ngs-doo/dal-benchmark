using Newtonsoft.Json;
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace GatherResults
{
	class Program
	{
		private static string BenchPath = "../../../app";
		private static string JavaPath = Environment.GetEnvironmentVariable("JAVA_HOME");

		static void Main(string[] args)
		{
			//args = new[] { "import", "results.json" };
			if (args.Length == 2 && args[0] == "import" && File.Exists(args[1]))
			{
				File.Copy("template.xlsx", "results.xlsx", true);
				var vms = JsonConvert.DeserializeObject<ViewModel[]>(File.ReadAllText(args[1]));
				using (var doc = NGS.Templater.Configuration.Factory.Open("results.xlsx"))
					doc.Process(vms);
				Process.Start("results.xlsx");
				return;
			}
			if (args.Length > 0) BenchPath = args[0];
			bool exeExists = File.Exists(Path.Combine(BenchPath, "DALBenchmark.exe"));
			bool jarExists = File.Exists(Path.Combine(BenchPath, "dal-benchmark.jar"));
			if (!exeExists && !jarExists)
			{
				if (args.Length > 0 || !File.Exists("DALBenchmark.exe"))
				{
					Console.WriteLine("Unable to find benchmark exe file: DALBenchmark.exe in" + BenchPath);
					return;
				}
				if (args.Length > 0 || !File.Exists("dal-benchmark.jar"))
				{
					Console.WriteLine("Unable to find benchmark jar file: dal-benchmark.jar in" + BenchPath);
					return;
				}
				BenchPath = ".";
			}
			var java = Path.Combine(JavaPath ?? ".", "bin", "java");
			var process =
				Process.Start(
					new ProcessStartInfo
					{
						FileName = java,
						Arguments = "-version",
						RedirectStandardOutput = true,
						UseShellExecute = false
					});
			var javaVersion = process.StandardOutput.ReadToEnd();
			Console.WriteLine(javaVersion);
			var efPostgres = GetherDuration("EF_Postgres", true);
			var sqlAdoNet = GetherDuration("MsSql_AdoNet", true);
			var npgsql = GetherDuration("Npgsql", true);
			var revenjPostgres = GetherDuration("Revenj_Postgres", true);
			var sqlOdpNet = GetherDuration("Oracle_OdpNet", true);
			//var revenjOracle = GetherDuration("Revenj_Oracle", true);
			File.Copy("template.xlsx", "results.xlsx", true);
			var vm = new ViewModel[]
			{
				new ViewModel("MsSql ADO.NET", sqlAdoNet, Database.MsSql, ".NET", ORM.None, "ADO.NET"),
				new ViewModel("Npgsql", npgsql, Database.Postgres, ".NET", ORM.None, "ADO.NET"),
				new ViewModel("Revenj Postgres", revenjPostgres, Database.Postgres, ".NET", ORM.Full, "Revenj"),
				new ViewModel("EF Postgres", efPostgres, Database.Postgres, ".NET", ORM.Full, "Entity Framework"),
				new ViewModel("Oracle ODP.NET", sqlAdoNet, Database.Oracle, ".NET", ORM.None, "ADO.NET"),
				//new ViewModel("Revenj Oracle", revenjOracle),
			};
			var json = JsonConvert.SerializeObject(vm);
			File.WriteAllText("results.json", json);
			using (var doc = NGS.Templater.Configuration.Factory.Open("results.xlsx"))
				doc.Process(vm);
			Process.Start("results.xlsx");
		}

		static Bench GetherDuration(string target, bool exe)
		{
			var simple = RunSinglePass("Simple 10k", exe, target, "Simple", 10000);
			var so = RunSinglePass("Standard objects 1k", exe, target, "Standard_Objects", 1000);
			var sr = RunSinglePass("Standard relations 1k", exe, target, "Standard_Relations", 1000);
			var co = RunSinglePass("Complex objects 300", exe, target, "Complex_Objects", 300);
			var cr = RunSinglePass("Complex relations 300", exe, target, "Complex_Relations", 300);
			return new Bench
			{
				simple = simple,
				standardObjects = so,
				standardRelations = sr,
				complexObjects = co,
				complexRelations = cr
			};
		}

		static Result RunSinglePass(string description, bool exe, string target, string type, int size)
		{
			var processName = exe ? Path.Combine(BenchPath, "DALBenchmark.exe") : Path.Combine(JavaPath ?? ".", "bin", "java");
			var jarArg = exe ? string.Empty : "-jar \"" + Path.Combine(BenchPath, "dal-benchmark.jar") + "\" ";
			var info = new ProcessStartInfo(processName, jarArg + target + " " + type + " " + size)
			{
				UseShellExecute = false,
				RedirectStandardOutput = true,
				RedirectStandardError = true,
				CreateNoWindow = true
			};
			Console.Write("Running " + description + " for " + target + " ...");
			var process = Process.Start(info);
			process.WaitForExit();
			Console.WriteLine("done (" + process.ExitCode + ")");
			if (process.ExitCode != 0)
				return null;
			var output = process.StandardOutput.ReadToEnd();
			Console.WriteLine(output);
			var lines = output.Split('\n');
			var parsed =
				(from l in lines.Take(11)
				 let parts = l.Split('=')
				 select new { key = parts[0].Trim(), value = int.Parse(parts[1].Trim()) })
				 .ToDictionary(it => it.key, it => it.value);
			return new Result
			{
				bulkInsert = parsed["bulk_insert"],
				bulkUpdate = parsed["bulk_update"],
				loopInsertHalf = parsed["loop_insert_half"],
				loopUpdateHalf = parsed["loop_update_half"],
				searchAll = parsed["search_all"],
				searchSubset = parsed["search_subset"],
				queryAll = Extract(parsed["query_all"]),
				queryFilter = Extract(parsed["query_filter"]),
				findMany = parsed["find_many"],
				findOne = parsed["find_one"],
				report = Extract(parsed["report"])
			};
		}

		static int? Extract(int value)
		{
			return value != -1 ? (int?)value : null;
		}
	}


	class Result
	{
		public int bulkInsert;
		public int bulkUpdate;
		public int loopInsertHalf;
		public int loopUpdateHalf;
		public int searchAll;
		public int searchSubset;
		public int? queryAll;
		public int? queryFilter;
		public int findMany;
		public int findOne;
		public int? report;
	}

	class Bench
	{
		public Result simple;
		public Result standardObjects;
		public Result standardRelations;
		public Result complexObjects;
		public Result complexRelations;
	}

	enum Database
	{
		MsSql,
		Postgres,
		Oracle,
		MySql
	}


	enum ORM
	{
		None,
		Micro,
		Full
	}

	class ViewModel
	{
		public string description;
		public Database database;
		public string platform;
		public ORM orm;
		public string api;
		public Bench bench;
		public ViewModel(string description, Bench bench, Database database, string platform, ORM orm, string api)
		{
			this.description = description;
			this.bench = bench;
			this.database = database;
			this.platform = platform;
			this.orm = orm;
			this.api = api;
		}
	}
}