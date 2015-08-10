package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.*;
import hr.ngs.benchmark.Simple.Post;
import org.revenj.extensibility.Container;
import org.revenj.patterns.AggregateRoot;
import org.revenj.patterns.PersistableRepository;
import org.revenj.patterns.ServiceLocator;
import org.revenj.patterns.Specification;

import java.io.IOException;
import java.math.BigDecimal;
import java.net.URI;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.ZoneOffset;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.stream.Stream;

public abstract class RevenjBench {
	public static void runBench(String connectionString, BenchType type, int data) throws Exception {
		switch (type) {
			case Simple:
				Bench<Post> simpleBench =
						new RevenjGenericBench(
								Post.class,
								connectionString,
								i -> new Post.FindBy(Factories.TODAY.plusDays(i), Factories.TODAY.plusDays(i + 10)),
								RevenjBench::getSimpleReport);
				Main.runBenchmark(
						Post.class,
						simpleBench,
						(value, i) -> {
							value.setId(Factories.GetUUID(i));
							value.setTitle("title " + i);
							value.setCreated(Factories.TODAY.plusDays(i));
						},
						(value, i) -> value.setTitle(value.getTitle() + "!"),
						data);
				break;
			case Standard_Objects:
				Bench<hr.ngs.benchmark.StandardObjects.Invoice> stdObjBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.StandardObjects.Invoice.class,
								connectionString,
								i -> new hr.ngs.benchmark.StandardObjects.Invoice.FindBy(i, i + 10),
								RevenjBench::getStandardObjectsReport);
				Main.runBenchmark(
						hr.ngs.benchmark.StandardObjects.Invoice.class,
						stdObjBench,
						(inv, i) -> {
							inv.setNumber(Integer.toString(i));
							inv.setTotal(BigDecimal.valueOf(100 + i));
							inv.setDueDate(Factories.TODAY.plusDays(i / 2));
							inv.setPaid(i % 3 == 0 ? Factories.TODAY.plusDays(i).atStartOfDay().atOffset(ZoneOffset.UTC) : null);
							inv.setReference(i % 7 == 0 ? Integer.toString(i) : null);
							inv.setTax(BigDecimal.valueOf(15 + i % 10));
							inv.setVersion(i);
							inv.setCanceled(i % 5 == 0);
							for (int j = 0; j < i % 10; j++) {
								inv.getItems().add(
										new hr.ngs.benchmark.StandardObjects.Item()
												.setProduct("prod " + i + " - " + j)
												.setCost(BigDecimal.valueOf((i + j * j) / 100))
												.setDiscount(BigDecimal.valueOf(i % 3 == 0 ? i % 10 + 5 : 0))
												.setQuantity(i / 100 + j / 2 + 1)
												.setTaxGroup(BigDecimal.valueOf(5 + i % 20)));
							}
						},
						(invoice, i) -> {
							invoice.setPaid(Factories.NOW_OFFSET.plusNanos(i * 1000));
							int len = invoice.getItems().size() / 3;
							for (hr.ngs.benchmark.StandardObjects.Item it : invoice.getItems()) {
								len--;
								if (len < 0) {
									return;
								}
								it.setProduct(it.getProduct() + " !");
							}
						},
						data);
				break;
			case Standard_Relations:
				Bench<hr.ngs.benchmark.StandardRelations.Invoice> stdRelBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.StandardRelations.Invoice.class,
								connectionString,
								i -> new hr.ngs.benchmark.StandardRelations.Invoice.FindBy(i, i + 10),
								RevenjBench::getStandardRelationalReport);
				Main.runBenchmark(
						hr.ngs.benchmark.StandardRelations.Invoice.class,
						stdRelBench,
						(inv, i) -> {
							inv.setNumber(Integer.toString(i));
							inv.setTotal(BigDecimal.valueOf(100 + i));
							inv.setDueDate(Factories.TODAY.plusDays(i / 2));
							inv.setPaid(i % 3 == 0 ? Factories.TODAY.plusDays(i).atStartOfDay().atOffset(ZoneOffset.UTC) : null);
							inv.setReference(i % 7 == 0 ? Integer.toString(i) : null);
							inv.setTax(BigDecimal.valueOf(15 + i % 10));
							inv.setVersion(i);
							inv.setCanceled(i % 5 == 0);
							for (int j = 0; j < i % 10; j++) {
								inv.getItems().add(
										new hr.ngs.benchmark.StandardRelations.Item()
												.setProduct("prod " + i + " - " + j)
												.setCost(BigDecimal.valueOf((i + j * j) / 100))
												.setDiscount(BigDecimal.valueOf(i % 3 == 0 ? i % 10 + 5 : 0))
												.setQuantity(i / 100 + j / 2 + 1)
												.setTaxGroup(BigDecimal.valueOf(5 + i % 20)));
							}
						},
						(invoice, i) -> {
							invoice.setPaid(Factories.NOW_OFFSET.plusNanos(i * 1000));
							int len = invoice.getItems().size() / 3;
							for (hr.ngs.benchmark.StandardRelations.Item it : invoice.getItems()) {
								len--;
								if (len < 0) {
									return;
								}
								it.setProduct(it.getProduct() + " !");
							}
						},
						data);
				break;
			case Complex_Objects:
				Bench<hr.ngs.benchmark.ComplexObjects.BankScrape> cplObjBench =
						new RevenjGenericBench(
								hr.ngs.benchmark.ComplexObjects.BankScrape.class,
								connectionString,
								i -> new hr.ngs.benchmark.ComplexObjects.BankScrape.FindBy(Factories.NOW_OFFSET.plusMinutes(i), Factories.NOW_OFFSET.plusMinutes(i + 10)),
								RevenjBench::getComplexObjectsReport);
				Main.runBenchmark(
						hr.ngs.benchmark.ComplexObjects.BankScrape.class,
						cplObjBench,
						(scrape, i) -> {
							scrape.setId(i);
							scrape.setWebsite(URI.create("https://dsl-platform.com/benchmark/" + i));
							List<String> tags = IntStream.range(i % 20, (i % 20) + (i % 6)).mapToObj(it -> "tag" + it).collect(Collectors.toList());
							scrape.setTags(new HashSet<>(tags));
							scrape.setInfo(new HashMap<>());
							fillDict(i, scrape.getInfo());
							scrape.setExternalId(i % 3 != 0 ? Integer.toString(i) : null);
							scrape.setRanking(i);
							scrape.setCreatedAt(Factories.NOW_OFFSET.plusMinutes(i));
							for (int j = 0; j < i % 10; j++) {
								hr.ngs.benchmark.ComplexObjects.Account acc = new hr.ngs.benchmark.ComplexObjects.Account();
								acc.setBalance(BigDecimal.valueOf(55 + i / (j + 1) - j * j));
								acc.setName( "acc " + i + " - " + j);
								acc.setNumber(i + "-" + j);
								acc.setNotes("some notes " + String.format("%" + (j * 10) + "d", i).replace(' ', 'x'));
								scrape.getAccounts().add(acc);
								for (int k = 0; k < (i + j) % 300; k++) {
									hr.ngs.benchmark.ComplexObjects.Transaction tran = new hr.ngs.benchmark.ComplexObjects.Transaction();
									tran.setAmount(BigDecimal.valueOf(i / (j + k + 100)));
									tran.setCurrency(hr.ngs.benchmark.Complex.Currency.values()[k % 3]);
									tran.setDate(Factories.TODAY.plusDays(i + j + k));
									tran.setDescription("transaction " + i + " at " + k);
									acc.getTransactions().add(tran);
								}
							}
						},
						(scrape, i) -> {
							scrape.setAt(Factories.NOW_OFFSET.plusNanos(i * 1000));
							int lenAcc = scrape.getAccounts().size() / 3;
							for (hr.ngs.benchmark.ComplexObjects.Account acc : scrape.getAccounts()) {
								lenAcc--;
								if (lenAcc < 0)
									return;
								acc.setBalance(acc.getBalance().add(BigDecimal.valueOf(10)));
								int lenTran = acc.getTransactions().size() / 5;
								for (hr.ngs.benchmark.ComplexObjects.Transaction tran : acc.getTransactions()) {
									lenTran--;
									if (lenTran < 0)
										break;
									tran.setAmount(tran.getAmount().add(BigDecimal.valueOf(5)));
								}
							}
						},
						data);
				break;
			default:
				throw new UnsupportedOperationException();
		}
	}

	private static void fillDict(int i, Map<String, String> dict) {
		for (int j = 0; j < i / 3 % 10; j++) {
			dict.put("key" + j, "value " + i);
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
						Factories.NOW_OFFSET.plusMinutes(i),
						Factories.NOW_OFFSET.plusMinutes(i + 6));
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

	interface MapReport<T> {
		Report<T> map(int i, ServiceLocator locator);
	}

	interface SearchWith {
		Specification create(int i);
	}

	static class RevenjGenericBench<T extends AggregateRoot> implements Bench<T> {

		private final ServiceLocator locator;
		private final PersistableRepository repository;
		private final Connection connection;
		private final SearchWith searchFilter;
		private final MapReport<T> mapReport;

		public RevenjGenericBench(
				Class<T> manifest,
				String connectionString,
				SearchWith searchFilter,
				MapReport<T> mapReport) throws Exception {
			this.locator = Boot.configure(connectionString);
			this.connection = locator.resolve(Connection.class);
			((Container) locator).registerInstance(Connection.class, connection, true);
			this.repository = locator.resolve(PersistableRepository.class, manifest);
			this.searchFilter = searchFilter;
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
		public Stream<T> stream() throws IOException {
			return repository.query().stream();
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
