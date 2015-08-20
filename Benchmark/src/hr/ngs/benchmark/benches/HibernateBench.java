package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.*;
import hr.ngs.benchmark.model.Invoice;
import hr.ngs.benchmark.model.Post;
import org.hibernate.*;
import org.hibernate.boot.registry.StandardServiceRegistryBuilder;
import org.hibernate.cfg.Configuration;
import org.hibernate.criterion.Order;
import org.hibernate.criterion.Restrictions;
import org.jinq.jpa.JinqJPAStreamProvider;
import org.jinq.orm.stream.JinqStream;
import org.revenj.patterns.AggregateRoot;

import javax.persistence.EntityManager;
import javax.persistence.EntityManagerFactory;
import javax.persistence.Persistence;
import java.io.Serializable;
import java.sql.*;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.logging.Level;

public abstract class HibernateBench {

	public static void runBench(String connectionString, BenchType type, int data) throws Exception {
		Connection connection = DriverManager.getConnection(connectionString);
		switch (type) {
			case Simple:
				Bench<Post> simpleBench =
						new GenericHibernateBench<>(
								Post.class,
								connection,
								UUID::fromString,
								(uris, criteria) -> {
									UUID[] ids = new UUID[uris.length];
									for (int i = 0; i < ids.length; i++) ids[i] = UUID.fromString(uris[i]);
									return criteria.add(Restrictions.in("id", ids));
								},
								(i, criteria) -> criteria
										.add(Restrictions.ge("created", Factories.TODAY.plusDays(i)))
										.add(Restrictions.le("created", Factories.TODAY.plusDays(i + 10))),
								HibernateBench::createSimpleReport);
				Main.runBenchmark(
						Post.class,
						simpleBench,
						Factories.newSimple(),
						Factories.updateSimple(),
						data);
				break;
			case Standard_Relations:
				Bench<Invoice> stdRelBench =
						new GenericHibernateBench<>(
								Invoice.class,
								connection,
								uri -> uri,
								(uris, criteria) -> criteria.add(Restrictions.in("number", uris)),
								(i, criteria) -> criteria
										.add(Restrictions.ge("version", (long) i))
										.add(Restrictions.le("version", (long) i + 10)),
								HibernateBench::createStandardReport);
				Main.runBenchmark(
						Invoice.class,
						stdRelBench,
						Factories.newStandard(),
						Factories.updateStandard(),
						data);
				break;
			default:
				throw new UnsupportedOperationException();
		}
	}

	static Report<Post> createSimpleReport(int i, Session session) {
		Report<Post> result = new Report<>();
		UUID id = Factories.GetUUID(i);
		UUID[] ids = new UUID[]{Factories.GetUUID(i), Factories.GetUUID(i + 2), Factories.GetUUID(i + 5), Factories.GetUUID(i + 7)};
		LocalDate start = Factories.TODAY.plusDays(i);
		LocalDate end = Factories.TODAY.plusDays(i + 6);
		result.findOne = (Post) session.createCriteria(Post.class)
				.add(Restrictions.eq("id", id))
				.list().get(0);
		result.findMany = session.createCriteria(Post.class)
				.add(Restrictions.in("id", ids))
				.list();
		result.findFirst = (Post) session.createCriteria(Post.class)
				.add(Restrictions.ge("created", start))
				.addOrder(Order.asc("created"))
				.setMaxResults(1)
				.list().get(0);
		result.findLast = (Post) session.createCriteria(Post.class)
				.add(Restrictions.le("created", end))
				.addOrder(Order.desc("created"))
				.setMaxResults(1)
				.list().get(0);
		result.topFive = session.createCriteria(Post.class)
				.add(Restrictions.ge("created", start))
				.add(Restrictions.le("created", end))
				.addOrder(Order.asc("created"))
				.setMaxResults(5)
				.list();
		result.lastTen = session.createCriteria(Post.class)
				.add(Restrictions.ge("created", start))
				.add(Restrictions.le("created", end))
				.addOrder(Order.desc("created"))
				.setMaxResults(10)
				.list();
		return result;
	}

	static Report<Invoice> createStandardReport(int i, Session session) {
		Report<Invoice> result = new Report<>();
		String id = Integer.toString(i);
		String[] ids = new String[]{Integer.toString(i), Integer.toString(i + 2), Integer.toString(i + 5), Integer.toString(i + 7)};
		long start = i;
		long end = i + 6;
		result.findOne = (Invoice) session.createCriteria(Invoice.class)
				.add(Restrictions.eq("number", id))
				.list().get(0);
		result.findMany = session.createCriteria(Invoice.class)
				.add(Restrictions.in("number", ids))
				.list();
		result.findFirst = (Invoice) session.createCriteria(Invoice.class)
				.add(Restrictions.ge("version", start))
				.addOrder(Order.asc("createdAt"))
				.setMaxResults(1)
				.list().get(0);
		result.findLast = (Invoice) session.createCriteria(Invoice.class)
				.add(Restrictions.le("version", end))
				.addOrder(Order.desc("createdAt"))
				.setMaxResults(1)
				.list().get(0);
		result.topFive = session.createCriteria(Invoice.class)
				.add(Restrictions.ge("version", start))
				.add(Restrictions.le("version", end))
				.addOrder(Order.asc("createdAt"))
				.setMaxResults(5)
				.list();
		result.lastTen = session.createCriteria(Invoice.class)
				.add(Restrictions.ge("version", start))
				.add(Restrictions.le("version", end))
				.addOrder(Order.desc("createdAt"))
				.setMaxResults(10)
				.list();
		return result;
	}

	static class GenericHibernateBench<T extends AggregateRoot> implements Bench<T> {
		private final Class<T> manifest;
		private final Session session;
		private final Connection connection;
		private final Function<String, Serializable> convertToPk;
		private final BiFunction<String[], Criteria, Criteria> inPk;
		private final SearchFilter searchFilter;
		private final ReportFactory<T> reportFactory;

		interface SearchFilter {
			Criteria applyFilter(int i, Criteria criteria);
		}

		interface ReportFactory<T> {
			Report<T> createReport(int i, Session session);
		}

		public GenericHibernateBench(
				Class<T> manifest,
				Connection connection,
				Function<String, Serializable> convertToPk,
				BiFunction<String[], Criteria, Criteria> inPk,
				SearchFilter searchFilter,
				ReportFactory<T> reportFactory) throws SQLException {
			this.manifest = manifest;
			this.convertToPk = convertToPk;
			this.inPk = inPk;
			this.searchFilter = searchFilter;
			this.reportFactory = reportFactory;
			java.util.logging.Logger.getLogger("org.hibernate").setLevel(Level.OFF);
			Configuration configuration = new Configuration();
			configuration.configure("hibernate_postgres.cfg.xml");
			configuration.addResource("Simple.hbm.xml");
			configuration.addResource("Standard.hbm.xml");
			StandardServiceRegistryBuilder ssrb = new StandardServiceRegistryBuilder().applySettings(configuration.getProperties());
			SessionFactory sessionFactory = configuration.buildSessionFactory(ssrb.build());
			this.connection = connection;
			this.session = sessionFactory.withOptions()
					.noInterceptor()
					.flushBeforeCompletion(true)
					.autoJoinTransactions(false)
					.clearEventListeners()
					.connection(connection).openSession();
		}

		@Override
		public void clean() {
			try {
				connection.setAutoCommit(true);
				session.createSQLQuery("DELETE FROM \"Simple\".\"Post\"").executeUpdate();
				session.createSQLQuery("DELETE FROM \"StandardRelations\".\"Invoice\"").executeUpdate();
				session.clear();
			} catch (SQLException e) {
				throw new RuntimeException(e);
			}
		}

		@Override
		public void analyze() {
			try {
				connection.setAutoCommit(true);
				session.createSQLQuery("ANALYZE").executeUpdate();
				session.clear();
			} catch (SQLException e) {
				throw new RuntimeException(e);
			}
		}

		@Override
		public List<T> searchAll() {
			try {
				return session.createCriteria(manifest).list();
			} finally {
				session.clear();
			}
		}

		@Override
		public List<T> searchSubset(int i) {
			try {
				return searchFilter.applyFilter(i, session.createCriteria(manifest)).list();
			} finally {
				session.clear();
			}
		}

		public T findSingle(String uri) {
			T result = session.get(manifest, convertToPk.apply(uri));
			session.evict(result);
			return result;
		}

		@Override
		public List<T> findMany(String[] ids) {
			try {
				return inPk.apply(ids, session.createCriteria(manifest)).list();
			} finally {
				session.clear();
			}
		}

		@Override
		public void insert(Collection<T> values) {
			try {
				connection.setAutoCommit(false);
				for (T p : values) {
					session.save(p);
				}
				session.flush();
				connection.commit();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void update(Collection<T> values) {
			try {
				connection.setAutoCommit(false);
				for (T p : values) {
					session.saveOrUpdate(p);
				}
				session.flush();
				connection.commit();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void insert(T value) {
			try {
				connection.setAutoCommit(true);
				session.save(value);
				session.flush();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void update(T value) {
			try {
				connection.setAutoCommit(true);
				session.saveOrUpdate(value);
				session.flush();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
			session.evict(value);
		}

		@Override
		public List<T> queryAll() {
			return null;
			//JinqStream<Invoice> stream = streams.streamAll(entityManager, Invoice.class);
			//return stream.toList();
		}

		@Override
		public List<T> querySubset(int i) {
			//JinqStream<Invoice> stream = streams.streamAll(entityManager, Invoice.class);
			//LocalDate start = Factories.TODAY.plusDays(i);
			//LocalDate end = Factories.TODAY.plusDays(i + 10);
			return null;// stream.where(it -> it.getCreated().compareTo(start) >= 0 && it.getCreated().compareTo(end) <= 0).toList();
		}

		@Override
		public Report<T> report(int i) {
			session.clear();
			return reportFactory.createReport(i, session);
		}
	}
}