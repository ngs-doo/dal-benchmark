package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.*;
import hr.ngs.benchmark.Report;
import hr.ngs.benchmark.Simple.Post;
import org.revenj.extensibility.Container;
import org.revenj.patterns.*;

import java.io.IOException;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.*;

public abstract class RevenjBench {
	public static void runBench(String connectionString, BenchType type, int data) throws Exception {
		switch (type) {
			case Simple:
				Bench<Post> simpleBench =
						new RevenjGenericBench(
								Post.class,
								connectionString,
								i -> new Post.FindBy(Factories.TODAY.plusDays(i), Factories.TODAY.plusDays(i + 10)),
								(query, i) -> {
									LocalDate start = Factories.TODAY.plusDays(i);
									LocalDate end = Factories.TODAY.plusDays(i + 10);
									return ((Query<Post>) query)
											.filter(it -> it.getCreated().compareTo(start) >= 0 && it.getCreated().compareTo(end) <= 0)
											.list();
								},
								RevenjBench::getSimpleReport);
				Main.runBenchmark(Post.class, simpleBench, Factories::newSimple, Factories::updateSimple, data);
				break;
			case Standard_Objects:
				Bench<hr.ngs.benchmark.StandardObjects.Invoice> stdObjBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.StandardObjects.Invoice.class,
								connectionString,
								i -> new hr.ngs.benchmark.StandardObjects.Invoice.FindBy(i, i + 10),
								(query, i) -> ((Query<hr.ngs.benchmark.StandardObjects.Invoice>) query)
										.filter(it -> it.getVersion() >= i && it.getVersion() <= (i + 10))
										.list(),
								RevenjBench::getStandardObjectsReport);
				Main.runBenchmark(
						hr.ngs.benchmark.StandardObjects.Invoice.class,
						stdObjBench,
						Factories::newStandard,
						Factories::updateStandard,
						data);
				break;
			case Standard_Relations:
				Bench<hr.ngs.benchmark.StandardRelations.Invoice> stdRelBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.StandardRelations.Invoice.class,
								connectionString,
								i -> new hr.ngs.benchmark.StandardRelations.Invoice.FindBy(i, i + 10),
								(query, i) -> ((Query<hr.ngs.benchmark.StandardObjects.Invoice>) query)
										.filter(it -> it.getVersion() >= i && it.getVersion() <= (i + 10))
										.list(),
								RevenjBench::getStandardRelationalReport);
				Main.runBenchmark(
						hr.ngs.benchmark.StandardRelations.Invoice.class,
						stdRelBench,
						Factories::newStandard,
						Factories::updateStandard,
						data);
				break;
			case Complex_Objects:
				Bench<hr.ngs.benchmark.ComplexObjects.BankScrape> cplObjBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.ComplexObjects.BankScrape.class,
								connectionString,
								i -> new hr.ngs.benchmark.ComplexObjects.BankScrape.FindBy(Factories.NOW.plusMinutes(i), Factories.NOW.plusMinutes(i + 10)),
								(query, i) -> {
									OffsetDateTime start = Factories.NOW.plusMinutes(i);
									OffsetDateTime end = Factories.NOW.plusMinutes(i + 10);
									return ((Query<hr.ngs.benchmark.ComplexObjects.BankScrape>) query)
											.filter(it -> it.getCreatedAt().compareTo(start) >= 0 && it.getCreatedAt().compareTo(end) <= 0)
											.list();
								},
								RevenjBench::getComplexObjectsReport);
				Main.runBenchmark(
						hr.ngs.benchmark.ComplexObjects.BankScrape.class,
						cplObjBench,
						Factories::newComplex,
						Factories::updateComplex,
						data);
				break;
			case Complex_Relations:
				Bench<hr.ngs.benchmark.ComplexRelations.BankScrape> cplRelBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.ComplexRelations.BankScrape.class,
								connectionString,
								i -> new hr.ngs.benchmark.ComplexRelations.BankScrape.FindBy(Factories.NOW.plusMinutes(i), Factories.NOW.plusMinutes(i + 10)),
								(query, i) -> {
									OffsetDateTime start = Factories.NOW.plusMinutes(i);
									OffsetDateTime end = Factories.NOW.plusMinutes(i + 10);
									return ((Query<hr.ngs.benchmark.ComplexRelations.BankScrape>) query)
											.filter(it -> it.getCreatedAt().compareTo(start) >= 0 && it.getCreatedAt().compareTo(end) <= 0)
											.list();
								},
								RevenjBench::getComplexRelationsReport);
				Main.runBenchmark(
						hr.ngs.benchmark.ComplexRelations.BankScrape.class,
						cplRelBench,
						Factories::newComplex,
						Factories::updateComplex,
						data);
				break;
			default:
				throw new UnsupportedOperationException();
		}
	}

	static Report<Post> getSimpleReport(int i, ServiceLocator locator) {
		hr.ngs.benchmark.Simple.FindMultiple find =
				new hr.ngs.benchmark.Simple.FindMultiple(
						Factories.GetUUID(i),
						new UUID[]{Factories.GetUUID(i), Factories.GetUUID(i + 2), Factories.GetUUID(i + 5), Factories.GetUUID(i + 7)},
						Factories.TODAY.plusDays(i),
						Factories.TODAY.plusDays(i + 6));
		hr.ngs.benchmark.Simple.FindMultiple.Result result = find.populate(locator);
		Report<Post> report = new Report<>();
		report.findOne = result.getFindOne();
		report.findMany = result.getFindMany();
		report.findFirst = result.getFindFirst();
		report.findLast = result.getFindLast();
		report.topFive = result.getTopFive();
		report.lastTen = result.getLastTen();
		return report;
	}

	static Report<hr.ngs.benchmark.StandardRelations.Invoice> getStandardRelationalReport(int i, ServiceLocator locator) {
		hr.ngs.benchmark.StandardRelations.FindMultiple find =
				new hr.ngs.benchmark.StandardRelations.FindMultiple(
						Integer.toString(i),
						new String[]{Integer.toString(i), Integer.toString(i + 2), Integer.toString(i + 5), Integer.toString(i + 7)},
						i,
						i + 6);
		hr.ngs.benchmark.StandardRelations.FindMultiple.Result result = find.populate(locator);
		Report<hr.ngs.benchmark.StandardRelations.Invoice> report = new Report<>();
		report.findOne = result.getFindOne();
		report.findMany = result.getFindMany();
		report.findFirst = result.getFindFirst();
		report.findLast = result.getFindLast();
		report.topFive = result.getTopFive();
		report.lastTen = result.getLastTen();
		return report;
	}

	static Report<hr.ngs.benchmark.StandardObjects.Invoice> getStandardObjectsReport(int i, ServiceLocator locator) {
		hr.ngs.benchmark.StandardObjects.FindMultiple find =
				new hr.ngs.benchmark.StandardObjects.FindMultiple(
						Integer.toString(i),
						new String[]{Integer.toString(i), Integer.toString(i + 2), Integer.toString(i + 5), Integer.toString(i + 7)},
						i,
						i + 6);
		hr.ngs.benchmark.StandardObjects.FindMultiple.Result result = find.populate(locator);
		Report<hr.ngs.benchmark.StandardObjects.Invoice> report = new Report<>();
		report.findOne = result.getFindOne();
		report.findMany = result.getFindMany();
		report.findFirst = result.getFindFirst();
		report.findLast = result.getFindLast();
		report.topFive = result.getTopFive();
		report.lastTen = result.getLastTen();
		return report;
	}

	static Report<hr.ngs.benchmark.ComplexObjects.BankScrape> getComplexObjectsReport(int i, ServiceLocator locator) {
		hr.ngs.benchmark.ComplexObjects.FindMultiple find =
				new hr.ngs.benchmark.ComplexObjects.FindMultiple(
						i,
						new int[]{i, i + 2, i + 5, i + 7},
						Factories.NOW.plusMinutes(i),
						Factories.NOW.plusMinutes(i + 6));
		hr.ngs.benchmark.ComplexObjects.FindMultiple.Result result = find.populate(locator);
		Report<hr.ngs.benchmark.ComplexObjects.BankScrape> report = new Report<>();
		report.findOne = result.getFindOne();
		report.findMany = result.getFindMany();
		report.findFirst = result.getFindFirst();
		report.findLast = result.getFindLast();
		report.topFive = result.getTopFive();
		report.lastTen = result.getLastTen();
		return report;
	}

	static Report<hr.ngs.benchmark.ComplexRelations.BankScrape> getComplexRelationsReport(int i, ServiceLocator locator) {
		hr.ngs.benchmark.ComplexRelations.FindMultiple find =
				new hr.ngs.benchmark.ComplexRelations.FindMultiple(
						i,
						new int[]{i, i + 2, i + 5, i + 7},
						Factories.NOW.plusMinutes(i),
						Factories.NOW.plusMinutes(i + 6));
		hr.ngs.benchmark.ComplexRelations.FindMultiple.Result result = find.populate(locator);
		Report<hr.ngs.benchmark.ComplexRelations.BankScrape> report = new Report<>();
		report.findOne = result.getFindOne();
		report.findMany = result.getFindMany();
		report.findFirst = result.getFindFirst();
		report.findLast = result.getFindLast();
		report.topFive = result.getTopFive();
		report.lastTen = result.getLastTen();
		return report;
	}

	interface MapReport<T> {
		Report<T> map(int i, ServiceLocator locator);
	}

	interface QueryRuntime<T extends DataSource> {
		List<T> run(Query<T> query, int i) throws IOException;
	}

	interface SearchWith {
		Specification create(int i);
	}

	static class RevenjGenericBench<T extends AggregateRoot> implements Bench<T> {

		private final ServiceLocator locator;
		private final PersistableRepository repository;
		private final Connection connection;
		private final SearchWith searchFilter;
		private final QueryRuntime<T> runQuery;
		private final MapReport<T> mapReport;

		public RevenjGenericBench(
				Class<T> manifest,
				String connectionString,
				SearchWith searchFilter,
				QueryRuntime<T> runQuery,
				MapReport<T> mapReport) throws Exception {
			this.locator = Boot.configure(connectionString);
			this.connection = locator.resolve(Connection.class);
			((Container) locator).registerInstance(Connection.class, connection, true);
			this.repository = locator.resolve(PersistableRepository.class, manifest);
			this.searchFilter = searchFilter;
			this.runQuery = runQuery;
			this.mapReport = mapReport;
		}

		@Override
		public void clean() throws IOException {
			repository.delete(repository.search());
		}

		@Override
		public void analyze() throws IOException {
			try {
				Statement stats = connection.createStatement();
				stats.execute("ANALYZE");
				stats.close();
			} catch (SQLException e) {
				throw new IOException(e);
			}
		}

		@Override
		public List<T> searchAll() {
			return repository.search();
		}

		@Override
		public List<T> searchSubset(int i) {
			return repository.search(searchFilter.create(i));
		}

		@Override
		public List<T> queryAll() throws IOException {
			return repository.query().list();
		}

		@Override
		public List<T> querySubset(int i) throws IOException {
			Query<T> query = repository.query();
			return runQuery.run(query, i);
		}

		@Override
		public T findSingle(String id) {
			return (T) repository.find(id).get();
		}

		@Override
		public List<T> findMany(String[] ids) {
			return repository.find(ids);
		}

		@Override
		public void insert(Collection<T> values) throws IOException {
			repository.insert(values);
		}

		@Override
		public void update(Collection<T> values) throws IOException {
			repository.update(values);
		}

		@Override
		public void insert(T value) throws IOException {
			repository.insert(value);
		}

		@Override
		public void update(T value) throws IOException {
			repository.update(value);
		}

		@Override
		public Report<T> report(int i) {
			return mapReport.map(i, locator);
		}
	}
}
