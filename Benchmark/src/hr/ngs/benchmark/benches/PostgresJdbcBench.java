package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.*;
import hr.ngs.benchmark.model.Invoice;
import hr.ngs.benchmark.model.InvoiceItem;
import hr.ngs.benchmark.model.Post;

import java.sql.*;
import java.sql.Date;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.*;

public abstract class PostgresJdbcBench  {
	public static void runBench(String connectionString, BenchType type, int data) throws Exception {
		switch (type) {
			case Simple:
				Bench<Post> simpleBench = new PostgresJdbcSimpleBench(connectionString);
				Main.runBenchmark(Post.class, simpleBench, Factories.newSimple(), Factories.updateSimple(), data);
				break;
			case Standard_Relations:
				Bench<Invoice> stdBench = new PostgresJdbcStandardBench(connectionString);
				Main.runBenchmark(Invoice.class, stdBench, Factories.newStandard(), Factories.updateStandard(), data);
				break;
			default:
				throw new UnsupportedOperationException();
		}
	}

	static class PostgresJdbcSimpleBench implements Bench<Post> {
		private final Connection connection;
		private final LocalDate today;

		public PostgresJdbcSimpleBench(String connectionString) throws SQLException {
			connection = DriverManager.getConnection(connectionString);
			this.today = Factories.TODAY;
		}

		@Override
		public void clean() {
			try {
				Statement cleanup = connection.createStatement();
				cleanup.execute("DELETE FROM \"Simple\".\"Post\"");
				cleanup.close();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void analyze() {
			try {
				Statement stats = connection.createStatement();
				stats.execute("ANALYZE");
				stats.close();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public List<Post> searchAll() {
			try {
				final List<Post> result = new ArrayList<>();
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\"")) {
					final ResultSet rs = statement.executeQuery();
					while (rs.next()) {
						result.add(new Post((UUID) rs.getObject(1), rs.getString(2), rs.getDate(3).toLocalDate()));
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
				final List<Post> result = new ArrayList<>();
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" p WHERE p.created >= ? AND p.created <= ?")) {
					statement.setDate(1, Date.valueOf(today.plusDays(i)));
					statement.setDate(2, Date.valueOf(today.plusDays(i + 10)));
					final ResultSet rs = statement.executeQuery();
					while (rs.next()) {
						result.add(new Post((UUID) rs.getObject(1), rs.getString(2), rs.getDate(3).toLocalDate()));
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
				try (PreparedStatement statement = connection.prepareStatement("SELECT title, created FROM \"Simple\".\"Post\" WHERE id = ?")) {
					statement.setObject(1, id);
					rs = statement.executeQuery();
					if (rs.next()) {
						return new Post(id, rs.getString(1), rs.getDate(2).toLocalDate());
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
					return new Post((UUID) rs.getObject(1), rs.getString(2), rs.getDate(3).toLocalDate());
				}
				return null;
			}
		}

		private static void executeCollection(PreparedStatement statement, List<Post> result) throws SQLException {
			try (ResultSet rs = statement.executeQuery()) {
				while (rs.next()) {
					result.add(new Post((UUID) rs.getObject(1), rs.getString(2), rs.getDate(3).toLocalDate()));
				}
			}
		}

		@Override
		public List<Post> findMany(String[] ids) {
			try {
				final UUID[] arg = new UUID[ids.length];
				for (int i = 0; i < ids.length; i++) {
					arg[i] = UUID.fromString(ids[i]);
				}
				final List<Post> result = new ArrayList<>(ids.length);
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE id = ANY(?)")) {
					statement.setArray(1, connection.createArrayOf("uuid", arg));
					executeCollection(statement, result);
				}
				return result;
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void insert(Collection<Post> values) {
			try {
				connection.setAutoCommit(false);
				try (PreparedStatement statement = connection.prepareStatement("INSERT INTO \"Simple\".\"Post\"(id, title, created) VALUES(?, ?, ?)")) {
					for (Post it : values) {
						statement.setObject(1, it.getId());
						statement.setString(2, it.getTitle());
						statement.setDate(3, java.sql.Date.valueOf(it.getCreated()));
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
		public void update(Collection<Post> values) {
			try {
				connection.setAutoCommit(false);
				try (PreparedStatement statement = connection.prepareStatement("UPDATE \"Simple\".\"Post\" SET id = ?, title = ?, created = ? WHERE id = ?")) {
					for (Post it : values) {
						statement.setObject(1, it.getId());
						statement.setString(2, it.getTitle());
						statement.setDate(3, Date.valueOf(it.getCreated()));
						statement.setObject(4, UUID.fromString(it.getURI()));
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
				try (PreparedStatement statement = connection.prepareStatement("INSERT INTO \"Simple\".\"Post\"(id, title, created) VALUES(?, ?, ?)")) {
					statement.setObject(1, value.getId());
					statement.setString(2, value.getTitle());
					statement.setDate(3, Date.valueOf(value.getCreated()));
					statement.executeUpdate();
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void update(Post value) {
			try {
				try (PreparedStatement statement = connection.prepareStatement("UPDATE \"Simple\".\"Post\" SET id = ?, title = ?, created = ? WHERE id = ?")) {
					statement.setObject(1, value.getId());
					statement.setString(2, value.getTitle());
					statement.setDate(3, Date.valueOf(value.getCreated()));
					statement.setObject(4, UUID.fromString(value.getURI()));
					statement.executeUpdate();
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}


		@Override
		public List<Post> queryAll() {
			return null;
		}

		@Override
		public List<Post> querySubset(int i) {
			return null;
		}

		@Override
		public Report<Post> report(int i) {
			Report<Post> result = new Report<>();
			UUID id = Factories.GetUUID(i);
			UUID[] ids = new UUID[]{Factories.GetUUID(i), Factories.GetUUID(i + 2), Factories.GetUUID(i + 5), Factories.GetUUID(i + 7)};
			Date start = Date.valueOf(today.plusDays(i));
			Date end = Date.valueOf(today.plusDays(i + 6));
			try {
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE id = ?")) {
					statement.setObject(1, id);
					result.findOne = executeSingle(statement);
				}
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE id = ANY(?)")) {
					statement.setArray(1, connection.createArrayOf("uuid", ids));
					executeCollection(statement, result.findMany);
				}
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created >= ? ORDER BY created ASC LIMIT 1")) {
					statement.setDate(1, start);
					result.findFirst = executeSingle(statement);
				}
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created <= ? ORDER BY created DESC LIMIT 1")) {
					statement.setDate(1, end);
					result.findLast = executeSingle(statement);
				}
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created >= ? AND created <= ? ORDER BY created ASC LIMIT 5")) {
					statement.setDate(1, start);
					statement.setDate(2, end);
					executeCollection(statement, result.topFive);
				}
				try (PreparedStatement statement = connection.prepareStatement("SELECT id, title, created FROM \"Simple\".\"Post\" WHERE created >= ? AND created <= ? ORDER BY created DESC LIMIT 10")) {
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

	static class PostgresJdbcStandardBench implements Bench<Invoice> {
		private final Connection connection;

		public PostgresJdbcStandardBench(String connectionString) throws SQLException {
			connection = DriverManager.getConnection(connectionString);
		}

		@Override
		public void clean() {
			try {
				Statement cleanup = connection.createStatement();
				cleanup.execute("DELETE FROM \"StandardRelations\".\"Item\"");
				cleanup.execute("DELETE FROM \"StandardRelations\".\"Invoice\"");
				cleanup.close();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void analyze() {
			try {
				Statement stats = connection.createStatement();
				stats.execute("ANALYZE");
				stats.close();
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		private static Invoice executeSingle(
				PreparedStatement stHead,
				PreparedStatement stChild,
				boolean setPk) throws SQLException {
			try (ResultSet rsHead = stHead.executeQuery()) {
				if (!rsHead.next()) {
					return null;
				}
				Invoice invoice = new Invoice(
						rsHead.getString(1),
						rsHead.getDate(2).toLocalDate(),
						rsHead.getBigDecimal(3),
						rsHead.getObject(4) == null ? null : rsHead.getTimestamp(4).toLocalDateTime().atOffset(ZoneOffset.UTC),
						rsHead.getBoolean(5),
						rsHead.getLong(6),
						rsHead.getBigDecimal(7),
						rsHead.getString(8),
						rsHead.getTimestamp(9).toLocalDateTime().atOffset(ZoneOffset.UTC),
						rsHead.getTimestamp(10).toLocalDateTime().atOffset(ZoneOffset.UTC));
				if (setPk) {
					stChild.setString(1, invoice.getNumber());
				}
				try (ResultSet rsChild = stChild.executeQuery()) {
					while (rsChild.next()) {
						invoice.getItems().add(
								new InvoiceItem(
										rsChild.getString(1),
										rsChild.getBigDecimal(2),
										rsChild.getInt(3),
										rsChild.getBigDecimal(4),
										rsChild.getBigDecimal(5)));
					}
				}
				return invoice;
			}
		}

		private static List<Invoice> executeCollection(
				PreparedStatement stHead,
				PreparedStatement stChild,
				Connection connection,
				boolean setPks) throws SQLException {
			Map<String, Invoice> map = new HashMap<>();
			Map<String, Integer> order = new HashMap<>();
			try (ResultSet rsHead = stHead.executeQuery()) {
				while (rsHead.next()) {
					String number = rsHead.getString(1);
					Invoice invoice = new Invoice(
							number,
							rsHead.getDate(2).toLocalDate(),
							rsHead.getBigDecimal(3),
							rsHead.getObject(4) == null ? null : rsHead.getTimestamp(4).toLocalDateTime().atOffset(ZoneOffset.UTC),
							rsHead.getBoolean(5),
							rsHead.getLong(6),
							rsHead.getBigDecimal(7),
							rsHead.getString(8),
							rsHead.getTimestamp(9).toLocalDateTime().atOffset(ZoneOffset.UTC),
							rsHead.getTimestamp(10).toLocalDateTime().atOffset(ZoneOffset.UTC));
					map.put(number, invoice);
					order.put(number, order.size());
				}
			}
			if (!map.isEmpty()) {
				if (setPks) {
					stChild.setArray(1, connection.createArrayOf("varchar", map.keySet().toArray(new String[map.size()])));
				}
				try (ResultSet rsChild = stChild.executeQuery()) {
					while (rsChild.next()) {
						String number = rsChild.getString(1);
						List<InvoiceItem> items = map.get(number).getItems();
						items.add(
								new InvoiceItem(
										rsChild.getString(2),
										rsChild.getBigDecimal(3),
										rsChild.getInt(4),
										rsChild.getBigDecimal(5),
										rsChild.getBigDecimal(6)));
					}
				}
			}
			Invoice[] result = new Invoice[map.size()];
			for (Map.Entry<String, Integer> kv : order.entrySet()) {
				result[kv.getValue()] = map.get(kv.getKey());
			}
			return Arrays.asList(result);
		}

		@Override
		public List<Invoice> searchAll() {
			try {
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" ORDER BY number");
				     PreparedStatement child = connection.prepareStatement("SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" ORDER BY \"Invoicenumber\", \"Index\"")) {
					return executeCollection(head, child, connection, false);
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public List<Invoice> searchSubset(int i) {
			try {
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version >= ? AND version <= ? ORDER BY number");
				     PreparedStatement child = connection.prepareStatement("SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ANY(?) ORDER BY \"Invoicenumber\", \"Index\"")) {
					head.setInt(1, i);
					head.setInt(2, i + 10);
					return executeCollection(head, child, connection, true);
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		public Invoice findSingle(String uri) {
			try {
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number = ?");
				     PreparedStatement child = connection.prepareStatement("SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ? ORDER BY \"Index\"")) {
					head.setString(1, uri);
					child.setString(1, uri);
					return executeSingle(head, child, false);
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public List<Invoice> findMany(String[] ids) {
			try {
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number = ANY(?) ORDER BY number");
				     PreparedStatement child = connection.prepareStatement("SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ANY(?) ORDER BY \"Invoicenumber\", \"Index\"")) {
					head.setArray(1, connection.createArrayOf("varchar", ids));
					child.setArray(1, connection.createArrayOf("varchar", ids));
					return executeCollection(head, child, connection, false);
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void insert(Collection<Invoice> values) {
			try {
				connection.setAutoCommit(false);
				try (PreparedStatement head = connection.prepareStatement("INSERT INTO \"StandardRelations\".\"Invoice\"(number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
				     PreparedStatement child = connection.prepareStatement("INSERT INTO \"StandardRelations\".\"Item\"(\"Invoicenumber\", \"Index\", product, cost, quantity, \"taxGroup\", discount) VALUES(?, ?, ?, ?, ?, ?, ?)")) {
					for (Invoice it : values) {
						head.setString(1, it.getNumber());
						head.setDate(2, Date.valueOf(it.getDueDate()));
						head.setBigDecimal(3, it.getTotal());
						head.setTimestamp(4, it.getPaid() != null ? Timestamp.valueOf(it.getPaid().toLocalDateTime()) : null);
						head.setBoolean(5, it.isCanceled());
						head.setLong(6, it.getVersion());
						head.setBigDecimal(7, it.getTax());
						head.setString(8, it.getReference());
						head.setTimestamp(9, Timestamp.valueOf(it.getCreatedAt().toLocalDateTime()));
						head.setTimestamp(10, Timestamp.valueOf(it.getModifiedAt().toLocalDateTime()));
						head.addBatch();
						for (int i = 0; i < it.getItems().size(); i++) {
							child.setString(1, it.getNumber());
							child.setInt(2, i);
							InvoiceItem det = it.getItems().get(i);
							child.setString(3, det.getProduct());
							child.setBigDecimal(4, det.getCost());
							child.setInt(5, det.getQuantity());
							child.setBigDecimal(6, det.getTaxGroup());
							child.setBigDecimal(7, det.getDiscount());
							child.addBatch();
						}
					}
					head.executeBatch();
					child.executeBatch();
				}
				connection.commit();
				connection.setAutoCommit(false);
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void update(Collection<Invoice> values) {
			try {
				connection.setAutoCommit(false);
				try (PreparedStatement info = connection.prepareStatement("SELECT COALESCE(MAX(\"Index\"), -1) FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ?");
				     PreparedStatement head = connection.prepareStatement("UPDATE \"StandardRelations\".\"Invoice\" SET number = ?, \"dueDate\" = ?, total = ?, paid = ?, canceled = ?, version = ?, tax = ?, reference = ?, \"modifiedAt\" = ? WHERE number = ?");
				     PreparedStatement childInsert = connection.prepareStatement("INSERT INTO \"StandardRelations\".\"Item\"(\"Invoicenumber\", \"Index\", product, cost, quantity, \"taxGroup\", discount) VALUES(?, ?, ?, ?, ?, ?, ?)");
				     PreparedStatement childUpdate = connection.prepareStatement("UPDATE \"StandardRelations\".\"Item\" SET product = ?, cost = ?, quantity = ?, \"taxGroup\" = ?, discount = ? WHERE \"Invoicenumber\" = ? AND \"Index\" = ?");
				     PreparedStatement childDelete = connection.prepareStatement("DELETE FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ? AND \"Index\" > ?")) {
					for(Invoice inv : values) {
						info.setString(1, inv.getURI());
						ResultSet rs = info.executeQuery();
						rs.next();
						int max = rs.getInt(1);
						rs.close();
						head.setString(1, inv.getNumber());
						head.setDate(2, Date.valueOf(inv.getDueDate()));
						head.setBigDecimal(3, inv.getTotal());
						head.setTimestamp(4, inv.getPaid() != null ? Timestamp.valueOf(inv.getPaid().toLocalDateTime()) : null);
						head.setBoolean(5, inv.isCanceled());
						head.setLong(6, inv.getVersion());
						head.setBigDecimal(7, inv.getTax());
						head.setString(8, inv.getReference());
						inv.setModifiedAt(OffsetDateTime.now(ZoneOffset.UTC));
						head.setTimestamp(9, Timestamp.valueOf(inv.getModifiedAt().toLocalDateTime()));
						head.setString(10, inv.getURI());
						head.addBatch();
						int min = Math.min(max, inv.getItems().size());
						for (int i = 0; i <= min; i++) {
							InvoiceItem det = inv.getItems().get(i);
							childUpdate.setString(1, det.getProduct());
							childUpdate.setBigDecimal(2, det.getCost());
							childUpdate.setInt(3, det.getQuantity());
							childUpdate.setBigDecimal(4, det.getTaxGroup());
							childUpdate.setBigDecimal(5, det.getDiscount());
							childUpdate.setString(6, inv.getNumber());
							childUpdate.setInt(7, i);
							childUpdate.addBatch();
						}
						for (int i = min + 1; i < inv.getItems().size(); i++) {
							InvoiceItem det = inv.getItems().get(i);
							childInsert.setString(1, inv.getNumber());
							childInsert.setInt(2, i);
							childInsert.setString(3, det.getProduct());
							childInsert.setBigDecimal(4, det.getCost());
							childInsert.setInt(5, det.getQuantity());
							childInsert.setBigDecimal(6, det.getTaxGroup());
							childInsert.setBigDecimal(7, det.getDiscount());
							childInsert.addBatch();
						}
						if (max > inv.getItems().size()) {
							childDelete.setString(1, inv.getNumber());
							childDelete.setInt(2, max);
							childDelete.addBatch();
						}
					}
					head.executeBatch();
					childInsert.executeBatch();
					childUpdate.executeBatch();
					childDelete.executeBatch();
				}
				connection.commit();
				connection.setAutoCommit(true);
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
		}

		@Override
		public void insert(Invoice value) {
			insert(Collections.singletonList(value));
		}

		@Override
		public void update(Invoice value) {
			update(Collections.singletonList(value));
		}


		@Override
		public List<Invoice> queryAll() {
			return null;
		}

		@Override
		public List<Invoice> querySubset(int i) {
			return null;
		}

		@Override
		public Report<Invoice> report(int i) {
			Report<Invoice> result = new Report<>();
			String id = Integer.toString(i);
			String[] ids = new String[]{Integer.toString(i), Integer.toString(i + 2), Integer.toString(i + 5), Integer.toString(i + 7)};
			int start = i;
			int end = i + 6;
			try {
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number = ?");
				     PreparedStatement child = connection.prepareStatement("SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ? ORDER BY \"Index\"")) {
					head.setString(1, id);
					child.setString(1, id);
					result.findOne = executeSingle(head, child, false);
				}
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE number = ANY(?) ORDER BY number");
				     PreparedStatement child = connection.prepareStatement("SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ANY(?) ORDER BY \"Invoicenumber\", \"Index\"")) {
					head.setArray(1, connection.createArrayOf("varchar", ids));
					child.setArray(1, connection.createArrayOf("varchar", ids));
					result.findMany = executeCollection(head, child, connection, false);
				}
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version >= ? ORDER BY \"createdAt\" LIMIT 1");
				     PreparedStatement child = connection.prepareStatement("SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ? ORDER BY \"Index\"")) {
					head.setInt(1, start);
					result.findFirst = executeSingle(head, child, true);
				}
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version <= ? ORDER BY \"createdAt\" DESC LIMIT 1");
				     PreparedStatement child = connection.prepareStatement("SELECT product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ? ORDER BY \"Index\"")) {
					head.setInt(1, end);
					result.findLast = executeSingle(head, child, true);
				}
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version >= ? AND version <= ? ORDER BY \"createdAt\", number LIMIT 5");
				     PreparedStatement child = connection.prepareStatement("SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ANY(?) ORDER BY \"Invoicenumber\", \"Index\"")) {
					head.setInt(1, start);
					head.setInt(2, end);
					result.topFive = executeCollection(head, child, connection, true);
				}
				try (PreparedStatement head = connection.prepareStatement("SELECT number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\" FROM \"StandardRelations\".\"Invoice\" WHERE version >= ? AND version <= ? ORDER BY \"createdAt\", number LIMIT 5");
				     PreparedStatement child = connection.prepareStatement("SELECT \"Invoicenumber\", product, cost, quantity, \"taxGroup\", discount FROM \"StandardRelations\".\"Item\" WHERE \"Invoicenumber\" = ANY(?) ORDER BY \"Invoicenumber\", \"Index\"")) {
					head.setInt(1, start);
					head.setInt(2, end);
					result.lastTen = executeCollection(head, child, connection, true);
				}
			} catch (SQLException ex) {
				throw new RuntimeException(ex);
			}
			return result;
		}
	}

}
