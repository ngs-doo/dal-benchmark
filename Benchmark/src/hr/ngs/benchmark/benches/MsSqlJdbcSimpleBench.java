package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.Factories;
import hr.ngs.benchmark.IBench;
import hr.ngs.benchmark.Report;
import hr.ngs.benchmark.model.Post;
import org.joda.time.LocalDate;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class MsSqlJdbcSimpleBench implements IBench<Post> {
	private final Connection connection;
	private final LocalDate today;

	public MsSqlJdbcSimpleBench(String connectionString) throws SQLException {
		connection = DriverManager.getConnection(connectionString);
		this.today = Factories.TODAY;
	}

	@Override
	public void clean() {
		try {
			Statement cleanup = connection.createStatement();
			cleanup.execute("DELETE FROM Post");
			cleanup.close();
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public void analyze() {
		try {
			Statement stats = connection.createStatement();
			stats.execute("UPDATE STATISTICS Post");
			stats.close();
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public List<Post> searchAll() {
		try {
			final List<Post> result = new ArrayList<Post>();
			try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM Post")) {
				final ResultSet rs = statement.executeQuery();
				while (rs.next()) {
					result.add(new Post(UUID.fromString(rs.getString(1)), rs.getString(2), LocalDate.fromDateFields(rs.getDate(3))));
				}
				rs.close();
			}
			return result;
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public List<Post> searchSubset(int i) {
		try {
			final List<Post> result = new ArrayList<Post>();
			try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM Post p WHERE p.created >= ? AND p.created <= ?")) {
				statement.setDate(1, new Date(today.plusDays(i).toDate().getTime()));
				statement.setDate(2, new Date(today.plusDays(i + 10).toDate().getTime()));
				final ResultSet rs = statement.executeQuery();
				while (rs.next()) {
					result.add(new Post(UUID.fromString(rs.getString(1)), rs.getString(2), LocalDate.fromDateFields(rs.getDate(3))));
				}
				rs.close();
			}
			return result;
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	public Post findSingle(String uri) {
		try {
			final UUID id = UUID.fromString(uri);
			ResultSet rs = null;
			try (PreparedStatement statement = connection.prepareStatement("SELECT title, created FROM Post WHERE id = ?")) {
				statement.setString(1, uri);
				rs = statement.executeQuery();
				if (rs.next()) {
					return new Post(id, rs.getString(1), LocalDate.fromDateFields(rs.getDate(2)));
				}
			} finally {
				if (rs != null) rs.close();
			}
			return null;
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	private static Post executeSingle(PreparedStatement statement) throws SQLException {
		try (ResultSet rs = statement.executeQuery()) {
			if (rs.next()) {
				return new Post(UUID.fromString(rs.getString(1)), rs.getString(2), LocalDate.fromDateFields(rs.getDate(3)));
			}
			return null;
		}
	}

	private static void executeCollection(PreparedStatement statement, List<Post> result) throws SQLException {
		try (ResultSet rs = statement.executeQuery()) {
			while (rs.next()) {
				result.add(new Post(UUID.fromString(rs.getString(1)), rs.getString(2), LocalDate.fromDateFields(rs.getDate(3))));
			}
		}
	}

	@Override
	public List<Post> findMany(String[] ids) {
		try {
			final List<Post> result = new ArrayList<Post>(ids.length);
			StringBuilder sb = new StringBuilder("SELECT id, title, created FROM Post WHERE id IN (?");
			for (int i = 1; i < ids.length; i++) {
				sb.append(",?");
			}
			sb.append(")");
			try (PreparedStatement statement = connection.prepareStatement(sb.toString())) {
				for (int i = 0; i < ids.length; i++) {
					statement.setString(i + 1, ids[i]);
				}
				executeCollection(statement, result);
			}
			return result;
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public void insert(Iterable<Post> values) {
		try {
			connection.setAutoCommit(false);
			try (PreparedStatement statement = connection.prepareStatement("INSERT INTO Post(id, title, created) VALUES(?, ?, ?)")) {
				for (Post it : values) {
					statement.setString(1, it.id.toString());
					statement.setString(2, it.title);
					statement.setDate(3, new Date(it.created.toDate().getTime()));
					statement.addBatch();
				}
				statement.executeBatch();
			}
			connection.commit();
			connection.setAutoCommit(true);
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public void update(Iterable<Post> values) {
		try {
			connection.setAutoCommit(false);
			try (PreparedStatement statement = connection.prepareStatement("UPDATE Post SET id = ?, title = ?, created = ? WHERE id = ?")) {
				for (Post it : values) {
					statement.setString(1, it.id.toString());
					statement.setString(2, it.title);
					statement.setDate(3, new Date(it.created.toDate().getTime()));
					statement.setString(4, it.getURI());
					statement.addBatch();
				}
				statement.executeBatch();
			}
			connection.commit();
			connection.setAutoCommit(true);
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public void insert(Post value) {
		try {
			try (PreparedStatement statement = connection.prepareStatement("INSERT INTO Post(id, title, created) VALUES(?, ?, ?)")) {
				statement.setString(1, value.id.toString());
				statement.setString(2, value.title);
				statement.setDate(3, new Date(value.created.toDate().getTime()));
				statement.executeUpdate();
			}
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public void update(Post value) {
		try {
			try (PreparedStatement statement = connection.prepareStatement("UPDATE Post SET id = ?, title = ?, created = ? WHERE id = ?")) {
				statement.setString(1, value.id.toString());
				statement.setString(2, value.title);
				statement.setDate(3, new Date(value.created.toDate().getTime()));
				statement.setString(4, value.getURI());
				statement.executeUpdate();
			}
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
	}

	@Override
	public Report<Post> report(int i) {
		Report<Post> result = new Report<Post>();
		UUID id = Factories.GetUUID(i);
		UUID[] ids = new UUID[]{Factories.GetUUID(i), Factories.GetUUID(i + 2), Factories.GetUUID(i + 5), Factories.GetUUID(i + 7)};
		Date start = new Date(today.plusDays(i).toDate().getTime());
		Date end = new Date(today.plusDays(i + 6).toDate().getTime());
		try {
			try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM Post WHERE id = ?")) {
				statement.setString(1, id.toString());
				result.findOne = executeSingle(statement);
			}
			try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM Post WHERE id IN (?, ?, ?, ?)")) {
				statement.setString(1, ids[0].toString());
				statement.setString(2, ids[1].toString());
				statement.setString(3, ids[2].toString());
				statement.setString(4, ids[3].toString());
				executeCollection(statement, result.findMany);
			}
			try (PreparedStatement statement = connection.prepareStatement("SELECT TOP 1 id, title, created FROM Post WHERE created >= ? ORDER BY created ASC")) {
				statement.setDate(1, start);
				result.findFirst = executeSingle(statement);
			}
			try (PreparedStatement statement = connection.prepareStatement("SELECT TOP 1 id, title, created FROM Post WHERE created <= ? ORDER BY created DESC")) {
				statement.setDate(1, end);
				result.findLast = executeSingle(statement);
			}
			try (PreparedStatement statement = connection.prepareStatement("SELECT TOP 5 id, title, created FROM Post WHERE created >= ? AND created <= ? ORDER BY created ASC")) {
				statement.setDate(1, start);
				statement.setDate(2, end);
				executeCollection(statement, result.topFive);
			}
			try (PreparedStatement statement = connection.prepareStatement("SELECT TOP 10 id, title, created FROM Post WHERE created >= ? AND created <= ? ORDER BY created DESC")) {
				statement.setDate(1, start);
				statement.setDate(2, end);
				executeCollection(statement, result.lastTen);
			}
		} catch (SQLException ex) {
			throw new RuntimeException(ex);
		}
		return result;
	}
}