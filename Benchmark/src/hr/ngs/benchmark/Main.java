package hr.ngs.benchmark;

import hr.ngs.benchmark.benches.PostgresJdbcSimpleBench;
import hr.ngs.benchmark.benches.PostgresJdbcStandardBench;
import hr.ngs.benchmark.model.Invoice;
import hr.ngs.benchmark.model.Post;

import java.io.InvalidObjectException;
import java.util.*;

public class Main {

	enum BenchTarget {
		Jdbc_Postgres, Jdbc_Psql
	}

	enum BenchType {
		Simple, Standard_Relational
	}

	static <T extends Enum> String enumTypes(T[] enums) {
		StringBuilder sb = new StringBuilder();
		sb.append(enums[0].name());
		for (int i = 1; i < enums.length; i++) {
			sb.append(" | ").append(enums[i].name());
		}
		return sb.toString();
	}

	public static void main(String[] args) {

		//args = new String[]{"Jdbc_Postgres", "Standard_Relational"};
		//args = new String[]{"Jdbc_Postgres", "Simple"};
		if (args.length != 2) {
			System.out.printf(
					"Expected usage: java -jar json-benchamrk.jar (%s) (%s)",
					enumTypes(BenchTarget.values()),
					enumTypes(BenchType.values()));
			return;
		}

		BenchTarget target;
		try {
			target = BenchTarget.valueOf(args[0]);
		} catch (Exception ex) {
			System.out.println("Unknown target found: " + args[0] + ". Supported targets: " + enumTypes(BenchTarget.values()));
			return;
		}

		BenchType type;
		try {
			type = BenchType.valueOf(args[1]);
		} catch (Exception ex) {
			System.out.println("Unknown type found: " + args[1] + ". Supported types: " + enumTypes(BenchType.values()));
			return;
		}

		try {
			String driver;
			switch (target) {
				case Jdbc_Postgres:
					driver = "postgresql";
					break;
				default:
					driver = "pgsql";
					break;
			}
			String connectionString = "jdbc:" + driver + "://localhost/Benchmark?user=postgres&password=6666";
			switch (type) {
				case Simple:
					IBench<Post> simpleBench = new PostgresJdbcSimpleBench(connectionString);
					runBenchmark(Post.class, simpleBench, Factories.newSimple(), Factories.updateSimple(), 10000);
					break;
				default:
					IBench<Invoice> stdBench = new PostgresJdbcStandardBench(connectionString);
					runBenchmark(Invoice.class, stdBench, Factories.newStandard(), Factories.updateStandard(), 1000);
					break;
			}
			System.exit(0);
		} catch (Exception ex) {
			System.out.println("error");
			ex.printStackTrace(System.out);
			System.exit(-2);
		}
	}

	private static long elapsedMilliseconds(Date from) {
		return new Date().getTime() - from.getTime();
	}

	private static <T extends IAggregateRoot> void runBenchmark(
			Class<T> manifest,
			IBench<T> bench,
			ModifyObject<T> fillNew,
			ModifyObject<T> changeExisting,
			int data) throws IllegalAccessException, InstantiationException, InvalidObjectException {
		for (int i = 0; i < 100; i++) {
			bench.clean();
			T newObject = manifest.newInstance();
			fillNew.run(newObject, i);
			bench.insert(newObject);
			bench.analyze();
			List<T> tmp = bench.searchAll();
			if (tmp.size() != 1)
				throw new InvalidObjectException("Incorrect results during search all");
			if (!newObject.equals(tmp.get(0)))
				throw new InvalidObjectException("Incorrect results when comparing aggregates from search");
			List<T> subset = bench.searchSubset(i);
			if (subset.size() != 1)
				throw new InvalidObjectException("Incorrect results during search subset, count=" + subset.size());
			changeExisting.run(tmp.get(0), i);
			bench.update(tmp);
			changeExisting.run(tmp.get(0), i);
			bench.update(tmp.get(0));
			T fs = bench.findSingle(newObject.getURI());
			if (!fs.equals(tmp.get(0)))
				throw new InvalidObjectException("Incorrect results when comparing aggregates from find single");
			List<T> fm = bench.findMany(new String[]{newObject.getURI()});
			if (fm.size() != 1)
				throw new InvalidObjectException("Incorrect results during find many");
			if (!fm.get(0).equals(tmp.get(0)))
				throw new InvalidObjectException("Incorrect results when comparing aggregates from find many");
			Report<T> rep = bench.report(i);
			if (rep != null) {
				if (rep.findMany.size() != 1 || rep.lastTen.size() != 1 || rep.topFive.size() != 1)
					throw new InvalidObjectException("Incorrect results during report");
				if (!rep.findOne.equals(tmp.get(0)) || !rep.findFirst.equals(tmp.get(0)) || !rep.findLast.equals(tmp.get(0))
						|| !rep.findMany.get(0).equals(tmp.get(0)) || !rep.lastTen.get(0).equals(tmp.get(0)) || !rep.topFive.get(0).equals(tmp.get(0)))
					throw new InvalidObjectException("Incorrect results when comparing aggregates from report");
			}
		}
		bench.clean();
		List<T> items = new ArrayList<T>(data);
		for (int i = 0; i < data; i++) {
			T t = manifest.newInstance();
			fillNew.run(t, i);
			items.add(t);
		}
		String[] lookupUris = new String[Math.min(10, Math.min(data / 2, data / 3 + 10) - data / 3)];
		Date dt = new Date();
		bench.insert(items);
		System.out.println("bulk_insert = " + elapsedMilliseconds(dt));
		for (int i = data / 3; i < data / 3 + lookupUris.length; i++)
			lookupUris[i - data / 3] = items.get(i).getURI();
		for (int i = 0; i < items.size(); i++)
			changeExisting.run(items.get(i), i);
		bench.analyze();
		dt = new Date();
		bench.update(items);
		System.out.println("bulk_update = " + elapsedMilliseconds(dt));
		bench.clean();
		dt = new Date();
		for (int i = 0; i < items.size() / 2; i++)
			bench.insert(items.get(i));
		System.out.println("loop_insert_half = " + elapsedMilliseconds(dt));
		for (int i = 0; i < items.size(); i++)
			changeExisting.run(items.get(i), i);
		bench.analyze();
		dt = new Date();
		for (int i = 0; i < items.size() / 2; i++)
			bench.update(items.get(i));
		System.out.println("loop_update_half = " + elapsedMilliseconds(dt));
		bench.analyze();
		dt = new Date();
		for (int i = 0; i < 100; i++) {
			int cnt = bench.searchAll().size();
			if (cnt != items.size() / 2)
				throw new InvalidObjectException("Expecting results");
		}
		System.out.println("search_all = " + elapsedMilliseconds(dt));
		dt = new Date();
		for (int i = 0; i < 3000; i++) {
			int cnt = bench.searchSubset(i % items.size() / 2).size();
			if (cnt == 0)
				throw new InvalidObjectException("Expecting results");
		}
		System.out.println("search_subset = " + elapsedMilliseconds(dt));
		System.out.println("query_all = -1");
		System.out.println("query_filter = -1");
		dt = new Date();
		for (int i = 0; i < 2000; i++) {
			int cnt = bench.findMany(lookupUris).size();
			if (cnt == 0)
				throw new InvalidObjectException("Expecting results");
		}
		System.out.println("find_many = " + elapsedMilliseconds(dt));
		dt = new Date();
		for (int i = 0; i < 5000; i++) {
			T res = bench.findSingle(lookupUris[i % lookupUris.length]);
			if (res == null)
				throw new InvalidObjectException("Expecting results");
		}
		System.out.println("find_one = " + elapsedMilliseconds(dt));
		Report<T> r = bench.report(0);
		if (r == null) {
			System.out.println("report = -1");
		} else {
			dt = new Date();
			for (int i = 0; i < 1000; i++) {
				Report<T> rr = bench.report(i % items.size() / 2);
				if (rr.lastTen.size() == 0 || rr.topFive.size() == 0 || rr.findMany.size() == 0
						|| rr.findFirst == null || rr.findLast == null || rr.findOne == null)
					throw new InvalidObjectException("Expecting results");
			}
			System.out.println("report = " + elapsedMilliseconds(dt));
		}
	}
}