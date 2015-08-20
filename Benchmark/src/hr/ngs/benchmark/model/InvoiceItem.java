package hr.ngs.benchmark.model;

import java.io.Serializable;
import java.math.BigDecimal;

public class InvoiceItem implements Serializable {
	private String product;
	private BigDecimal cost;
	private int quantity;
	private BigDecimal taxGroup;
	private BigDecimal discount;
	private Invoice invoice;
	private int index;

	public String getInvoiceNumber() {
		return invoice != null ? invoice.getNumber() : null;
	}

	public void setInvoiceNumber(String number) {
	}

	public InvoiceItem() {
		setProduct("");
		setCost(BigDecimal.ZERO);
		setTaxGroup(BigDecimal.ZERO);
		setDiscount(BigDecimal.ZERO);
	}

	public InvoiceItem(String product, BigDecimal cost, int quantity, BigDecimal taxGroup, BigDecimal discount) {
		this.setProduct(product);
		this.setCost(cost);
		this.setQuantity(quantity);
		this.setTaxGroup(taxGroup);
		this.setDiscount(discount);
	}

	public String getProduct() {
		return product;
	}

	public void setProduct(String product) {
		this.product = product;
	}

	public BigDecimal getCost() {
		return cost;
	}

	public void setCost(BigDecimal cost) {
		this.cost = cost;
	}

	public int getQuantity() {
		return quantity;
	}

	public void setQuantity(int quantity) {
		this.quantity = quantity;
	}

	public BigDecimal getTaxGroup() {
		return taxGroup;
	}

	public void setTaxGroup(BigDecimal taxGroup) {
		this.taxGroup = taxGroup;
	}

	public BigDecimal getDiscount() {
		return discount;
	}

	public void setDiscount(BigDecimal discount) {
		this.discount = discount;
	}

	public Invoice getInvoice() {
		return invoice;
	}

	public void setInvoice(Invoice invoice) {
		this.invoice = invoice;
	}

	public int getIndex() {
		return index;
	}

	public void setIndex(int index) {
		this.index = index;
	}
}
