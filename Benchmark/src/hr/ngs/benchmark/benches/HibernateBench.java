package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.*;
import hr.ngs.benchmark.model.Post;
import org.hibernate.*;
import org.hibernate.boot.registry.StandardServiceRegistryBuilder;
import org.hibernate.cfg.Configuration;
import org.hibernate.criterion.Order;
import org.hibernate.criterion.Restrictions;
import org.jinq.jpa.JinqJPAStreamProvider;
import org.jinq.orm.stream.JinqStream;

import javax.persistence.EntityManager;
import javax.persistence.EntityManagerFactory;
import javax.persistence.Persistence;
import java.sql.*;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import java.util.logging.Level;

public abstract class HibernateBench {

	public static void runBench(String connectionString, BenchType type, int data) throws Exception {
		switch (type) {
			case Simple:
				Bench<Post> simpleBench = new HibernateSimpleStatelessBench("hibernate_postgres.cfg.xml", connectionString);
				Main.runBenchmark(
						Post.class,
						simpleBench,
						Factories.newSimple(),
						Factories.updateSimple(),
						data);
				break;
			default:
				throw new UnsupportedOperationException();
		}
	}

	static class HibernateSimpleStatelessBench implements Bench<Post> {
		private final LocalDate today;
		private final StatelessSession session;
		private final Connection connection;
		private final EntityManager entityManager;
		private final JinqJPAStreamProvider streams;

		public HibernateSimpleStatelessBench(String config, String connectionString) throws SQLException {
			this.today = Factories.TODAY;
			java.util.logging.Logger.getLogger("org.hibernate").setLevel(Level.OFF);
			Configuration configuration = new Configuration();
			configuration.configure(config);
			configuration.addResource("Post.hbm.xml");
			StandardServiceRegistryBuilder ssrb = new StandardServiceRegistryBuilder().applySettings(configuration.getProperties());
			SessionFactory sessionFactory = configuration.buildSessionFactory(ssrb.build());
			this.connection = DriverManager.getConnection(connectionString);
			this.session = sessionFactory.openStatelessSession(connection);
			EntityManagerFactory entityManagerFactory = Persistence.createEntityManagerFactory("JPA");
			streams = new JinqJPAStreamProvider(entityManagerFactory);
			entityManager = entityManagerFactory.createEntityManager();
		}

		@Override
		public void clean() {
			try {
				connection.setAutoCommit(true);
				session.createSQLQuery("DELETE FROM \"Simple\".\"Post\"").executeUpdate();
			} catch (SQLException e) {
				throw new RuntimeException(e);
			}
		}

		@Override
		public void analyze() {
			try {
				connection.setAutoCommit(true);
				session.createSQLQuery("ANALYZE").executeUpdate();
			} catch (SQLException e) {
				throw new RuntimeException(e);
			}
		}

		@Override
		public List<Post> searchAll() {
			return session.createCriteria(Post.class).list();
		}

		@Override
		public List<Post> searchSubset(int i) {
			return session.createCriteria(Post.class)
					.add(Restrictions.ge("created", today.plusDays(i)))
					.add(Restrictions.le("created", today.plusDays(i + 10)))
					.list();
		}

		public Post findSingle(String uri) {
			return (Post) session.get(Post.class, UUID.fromString(uri));
		}

		@Override
		public List<Post> findMany(String[] ids) {
			UUID[] pks = new UUID[ids.length];
			for (int i = 0; i < ids.length; i++) {
				pks[i] = UUID.fromString(ids[i]);
			}
			return session.createCriteria(Post.class)
					.add(Restrictions.in("id", pks))
					.list();
		}

		@Override
		public void insert(Collection<Post> values) {
			try {
				connection.setAutoCommit(false);
				for (Post p : values) {
					session.insert(p);
				}
				connection.commit();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void update(Collection<Post> values) {
			try {
				connection.setAutoCommit(false);
				for (Post p : values) {
					session.update(p);
				}
				connection.commit();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void insert(Post value) {
			try {
				connection.setAutoCommit(true);
				session.insert(value);
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void update(Post value) {
			try {
				connection.setAutoCommit(true);
				session.update(value);
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public List<Post> queryAll() {
			JinqStream<Post> stream = streams.streamAll(entityManager, Post.class);
			return stream.toList();
		}

		@Override
		public List<Post> querySubset(int i) {
			JinqStream<Post> stream = streams.streamAll(entityManager, Post.class);
			LocalDate start = Factories.TODAY.plusDays(i);
			LocalDate end = Factories.TODAY.plusDays(i + 10);
			return null;// stream.where(it -> it.getCreated().compareTo(start) >= 0 && it.getCreated().compareTo(end) <= 0).toList();
		}

		@Override
		public Report<Post> report(int i) {
			Report<Post> result = new Report<>();
			UUID id = Factories.GetUUID(i);
			UUID[] ids = new UUID[]{Factories.GetUUID(i), Factories.GetUUID(i + 2), Factories.GetUUID(i + 5), Factories.GetUUID(i + 7)};
			LocalDate start = today.plusDays(i);
			LocalDate end = today.plusDays(i + 6);
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
	}
}