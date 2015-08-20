package hr.ngs.benchmark.model;

import org.revenj.patterns.AggregateRoot;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

public class Invoice implements AggregateRoot {
	private String number;
	private LocalDate dueDate;
	private BigDecimal total;
	private OffsetDateTime paid;
	private boolean canceled;
	private long version;
	private BigDecimal tax;
	private String reference;
	private OffsetDateTime createdAt;
	private OffsetDateTime modifiedAt;
	private List<InvoiceItem> items = new ArrayList<>();
	private String URI;

	public Invoice() {
		setNumber("");
		setDueDate(LocalDate.now());
		setTotal(BigDecimal.ZERO);
		setTax(BigDecimal.ZERO);
		setCreatedAt(OffsetDateTime.now());
		setModifiedAt(OffsetDateTime.now());
	}

	public Invoice(
			String number, LocalDate dueDate, BigDecimal total, OffsetDateTime paid, boolean canceled, long version,
			BigDecimal tax, String reference, OffsetDateTime createdAt, OffsetDateTime modifiedAt) {
		this.setNumber(number);
		this.setDueDate(dueDate);
		this.setTotal(total);
		this.setPaid(paid);
		this.setCanceled(canceled);
		this.setVersion(version);
		this.setTax(tax);
		this.setReference(reference);
		this.setCreatedAt(createdAt);
		this.setModifiedAt(modifiedAt);
	}

	@Override
	public String getURI() {
		if (URI == null) {
			URI = getNumber();
		}
		return URI;
	}

	@Override
	public int hashCode() {
		return getNumber().hashCode();
	}

	@Override
	public boolean equals(Object other) {
		if (other == null || !(other instanceof Invoice)) {
			return false;
		}
		Invoice value = (Invoice)other;
		return value.getNumber().equals(this.getNumber())
				&& value.getDueDate().equals(this.getDueDate())
				&& value.getTotal().equals(this.getTotal())
				&& value.getItems().size() ==  this.getItems().size()
				//...
				&& value.getCreatedAt().equals(this.getCreatedAt())
				&& value.getModifiedAt().equals(this.getModifiedAt());
	}

	public String getNumber() {
		return number;
	}

	public void setNumber(String number) {
		this.number = number;
	}

	public LocalDate getDueDate() {
		return dueDate;
	}

	public void setDueDate(LocalDate dueDate) {
		this.dueDate = dueDate;
	}

	public BigDecimal getTotal() {
		return total;
	}

	public void setTotal(BigDecimal total) {
		this.total = total;
	}

	public OffsetDateTime getPaid() {
		return paid;
	}

	public void setPaid(OffsetDateTime paid) {
		this.paid = paid;
	}

	public boolean isCanceled() {
		return canceled;
	}

	public void setCanceled(boolean canceled) {
		this.canceled = canceled;
	}

	public long getVersion() {
		return version;
	}

	public void setVersion(long version) {
		this.version = version;
	}

	public BigDecimal getTax() {
		return tax;
	}

	public void setTax(BigDecimal tax) {
		this.tax = tax;
	}

	public String getReference() {
		return reference;
	}

	public void setReference(String reference) {
		this.reference = reference;
	}

	public OffsetDateTime getCreatedAt() {
		return createdAt;
	}

	public void setCreatedAt(OffsetDateTime createdAt) {
		this.createdAt = createdAt;
	}

	public OffsetDateTime getModifiedAt() {
		return modifiedAt;
	}

	public void setModifiedAt(OffsetDateTime modifiedAt) {
		this.modifiedAt = modifiedAt;
	}

	public List<InvoiceItem> getItems() {
		return items;
	}

	public void setItems(List<InvoiceItem> items) {
		this.items = items;
	}

	public void addItem(InvoiceItem item) {
		item.setInvoice(this);
		item.setIndex(items.size());
		getItems().add(item);
	}
}
