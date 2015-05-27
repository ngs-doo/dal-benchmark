package hr.ngs.benchmark.model;

import hr.ngs.benchmark.IAggregateRoot;
import org.joda.time.DateTime;
import org.joda.time.LocalDate;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class Invoice implements IAggregateRoot {
	public String number;
	public LocalDate dueDate;
	public BigDecimal total;
	public DateTime paid;
	public boolean canceled;
	public long version;
	public BigDecimal tax;
	public String reference;
	public DateTime createdAt;
	public DateTime modifiedAt;
	public List<Item> items = new ArrayList<Item>();
	private String URI;

	public Invoice() {
		number = "";
		dueDate = LocalDate.now();
		total = BigDecimal.ZERO;
		tax = BigDecimal.ZERO;
		createdAt = DateTime.now();
		modifiedAt = DateTime.now();
	}

	public Invoice(
			String number, LocalDate dueDate, BigDecimal total, DateTime paid, boolean canceled, long version,
			BigDecimal tax, String reference, DateTime createdAt, DateTime modifiedAt) {
		this.number = number;
		this.dueDate = dueDate;
		this.total = total;
		this.paid = paid;
		this.canceled = canceled;
		this.version = version;
		this.tax = tax;
		this.reference = reference;
		this.createdAt = createdAt;
		this.modifiedAt = modifiedAt;
	}

	@Override
	public String getURI() {
		if (URI == null) {
			URI = number;
		}
		return URI;
	}

	@Override
	public int hashCode() {
		return number.hashCode();
	}

	@Override
	public boolean equals(Object other) {
		if (other == null || !(other instanceof Invoice)) {
			return false;
		}
		Invoice value = (Invoice)other;
		return value.number.equals(this.number)
				&& value.dueDate.equals(this.dueDate)
				&& value.total.equals(this.total)
				//...
				&& value.createdAt.equals(this.createdAt)
				&& value.modifiedAt.equals(this.modifiedAt);
	}

	public static class Item {
		public String product;
		public BigDecimal cost;
		public int quantity;
		public BigDecimal taxGroup;
		public BigDecimal discount;

		public Item() {
			product = "";
			cost = BigDecimal.ZERO;
			taxGroup = BigDecimal.ZERO;
			discount = BigDecimal.ZERO;
		}

		public Item(String product, BigDecimal cost, int quantity, BigDecimal taxGroup, BigDecimal discount) {
			this.product = product;
			this.cost = cost;
			this.quantity = quantity;
			this.taxGroup = taxGroup;
			this.discount = discount;
		}
	}
}
