package hr.ngs.benchmark.model;

import org.revenj.patterns.AggregateRoot;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

public class Invoice implements AggregateRoot {
	public String number;
	public LocalDate dueDate;
	public BigDecimal total;
	public LocalDateTime paid;
	public boolean canceled;
	public long version;
	public BigDecimal tax;
	public String reference;
	public LocalDateTime createdAt;
	public LocalDateTime modifiedAt;
	public List<Item> items = new ArrayList<>();
	private String URI;

	public Invoice() {
		number = "";
		dueDate = LocalDate.now();
		total = BigDecimal.ZERO;
		tax = BigDecimal.ZERO;
		createdAt = LocalDateTime.now();
		modifiedAt = LocalDateTime.now();
	}

	public Invoice(
			String number, LocalDate dueDate, BigDecimal total, LocalDateTime paid, boolean canceled, long version,
			BigDecimal tax, String reference, LocalDateTime createdAt, LocalDateTime modifiedAt) {
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
