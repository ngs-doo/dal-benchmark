package hr.ngs.benchmark.benches;

import hr.ngs.benchmark.IBench;
import hr.ngs.benchmark.Report;
import hr.ngs.benchmark.model.Invoice;
import org.joda.time.DateTime;
import org.joda.time.LocalDate;

import java.sql.*;
import java.sql.Date;
import java.util.*;

public class PostgresJdbcStandardBench implements IBench<Invoice> {
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
					new LocalDate(rsHead.getDate(2)),
					rsHead.getBigDecimal(3),
					rsHead.getObject(4) == null ? null : new DateTime(rsHead.getTimestamp(4)),
					rsHead.getBoolean(5),
					rsHead.getLong(6),
					rsHead.getBigDecimal(7),
					rsHead.getString(8),
					new DateTime(rsHead.getTimestamp(9)),
					new DateTime(rsHead.getTimestamp(10)));
			if (setPk) {
				stChild.setString(1, invoice.number);
			}
			try (ResultSet rsChild = stChild.executeQuery()) {
				while (rsChild.next()) {
					invoice.items.add(
							new Invoice.Item(
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
		Map<String, Invoice> map = new HashMap<String, Invoice>();
		Map<String, Integer> order = new HashMap<String, Integer>();
		try (ResultSet rsHead = stHead.executeQuery()) {
			while (rsHead.next()) {
				String number = rsHead.getString(1);
				Invoice invoice = new Invoice(
						number,
						new LocalDate(rsHead.getDate(2)),
						rsHead.getBigDecimal(3),
						rsHead.getObject(4) == null ? null : new DateTime(rsHead.getTimestamp(4)),
						rsHead.getBoolean(5),
						rsHead.getLong(6),
						rsHead.getBigDecimal(7),
						rsHead.getString(8),
						new DateTime(rsHead.getTimestamp(9)),
						new DateTime(rsHead.getTimestamp(10)));
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
					List<Invoice.Item> items = map.get(number).items;
					items.add(
							new Invoice.Item(
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
	public void insert(Iterable<Invoice> values) {
		try {
			connection.setAutoCommit(false);
			try (PreparedStatement head = connection.prepareStatement("INSERT INTO \"StandardRelations\".\"Invoice\"(number, \"dueDate\", total, paid, canceled, version, tax, reference, \"createdAt\", \"modifiedAt\") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
				 PreparedStatement child = connection.prepareStatement("INSERT INTO \"StandardRelations\".\"Item\"(\"Invoicenumber\", \"Index\", product, cost, quantity, \"taxGroup\", discount) VALUES(?, ?, ?, ?, ?, ?, ?)")) {
				for (Invoice it : values) {
					head.setString(1, it.number);
					head.setDate(2, new Date(it.dueDate.toDate().getTime()));
					head.setBigDecimal(3, it.total);
					head.setTimestamp(4, it.paid != null ? new Timestamp(it.paid.toDate().getTime()) : null);
					head.setBoolean(5, it.canceled);
					head.setLong(6, it.version);
					head.setBigDecimal(7, it.tax);
					head.setString(8, it.reference);
					head.setTimestamp(9, new Timestamp(it.createdAt.toDate().getTime()));
					head.setTimestamp(10, new Timestamp(it.modifiedAt.toDate().getTime()));
					head.addBatch();
					for (int i = 0; i < it.items.size(); i++) {
						child.setString(1, it.number);
						child.setInt(2, i);
						Invoice.Item det = it.items.get(i);
						child.setString(3, det.product);
						child.setBigDecimal(4, det.cost);
						child.setInt(5, det.quantity);
						child.setBigDecimal(6, det.taxGroup);
						child.setBigDecimal(7, det.discount);
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
	public void update(Iterable<Invoice> values) {
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
					head.setString(1, inv.number);
					head.setDate(2, new Date(inv.dueDate.toDate().getTime()));
					head.setBigDecimal(3, inv.total);
					head.setTimestamp(4, inv.paid != null ? new Timestamp(inv.paid.toDate().getTime()) : null);
					head.setBoolean(5, inv.canceled);
					head.setLong(6, inv.version);
					head.setBigDecimal(7, inv.tax);
					head.setString(8, inv.reference);
					inv.modifiedAt = DateTime.now();
					head.setTimestamp(9, new Timestamp(inv.modifiedAt.toDate().getTime()));
					head.setString(10, inv.getURI());
					head.addBatch();
					int min = Math.min(max, inv.items.size());
					for (int i = 0; i <= min; i++) {
						Invoice.Item det = inv.items.get(i);
						childUpdate.setString(1, det.product);
						childUpdate.setBigDecimal(2, det.cost);
						childUpdate.setInt(3, det.quantity);
						childUpdate.setBigDecimal(4, det.taxGroup);
						childUpdate.setBigDecimal(5, det.discount);
						childUpdate.setString(6, inv.number);
						childUpdate.setInt(7, i);
						childUpdate.addBatch();
					}
					for (int i = min + 1; i < inv.items.size(); i++) {
						Invoice.Item det = inv.items.get(i);
						childInsert.setString(1, inv.number);
						childInsert.setInt(2, i);
						childInsert.setString(3, det.product);
						childInsert.setBigDecimal(4, det.cost);
						childInsert.setInt(5, det.quantity);
						childInsert.setBigDecimal(6, det.taxGroup);
						childInsert.setBigDecimal(7, det.discount);
						childInsert.addBatch();
					}
					if (max > inv.items.size()) {
						childDelete.setString(1, inv.number);
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
	public Report<Invoice> report(int i) {
		Report<Invoice> result = new Report<Invoice>();
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
