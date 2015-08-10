package hr.ngs.benchmark;

import hr.ngs.benchmark.model.Invoice;
import hr.ngs.benchmark.model.Post;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.util.UUID;

public abstract class Factories {

	public static final LocalDate TODAY = LocalDate.now();
	public static final LocalDateTime NOW = LocalDateTime.now();
	public static final OffsetDateTime NOW_OFFSET = OffsetDateTime.now();

	public static UUID GetUUID(int i) {
		return new UUID(i, 0);
	}

	public static ModifyObject<Post> newSimple() {
		return (value, i) -> {
			value.setId(GetUUID(i));
			value.setTitle("title " + i);
			value.setCreated(TODAY.plusDays(i));
		};
	}

	public static ModifyObject<Post> updateSimple() {
		return (value, i) -> value.setTitle(value.getTitle() + "!");
	}

	public static ModifyObject<Invoice> newStandard() {
		return (inv, i) -> {
			inv.number = Integer.toString(i);
			inv.total = BigDecimal.valueOf(100 + i);
			inv.dueDate = TODAY.plusDays(i / 2);
			inv.paid = i % 3 == 0 ? TODAY.plusDays(i).atStartOfDay() : null;
			inv.reference = i % 7 == 0 ? Integer.toString(i) : null;
			inv.tax = BigDecimal.valueOf(15 + i % 10);
			inv.version = i;
			inv.canceled = i % 5 == 0;
			for (int j = 0; j < i % 10; j++)
			{
				Invoice.Item item = new Invoice.Item();
				item.product = "prod " + i + " - " + j;
				item.cost = BigDecimal.valueOf ((i + j * j) / 100);
				item.discount = BigDecimal.valueOf(i % 3 == 0 ? i % 10 + 5 : 0);
				item.quantity = i / 100 + j / 2 + 1;
				item.taxGroup = BigDecimal.valueOf(5 + i % 20);
				inv.items.add(item);
			}
		};
	}

	public static ModifyObject<Invoice> updateStandard() {
		return (invoice, i) -> {
			invoice.paid = NOW.plusNanos(i * 1000);
			int len = invoice.items.size() / 3;
			for(Invoice.Item it : invoice.items) {
				len--;
				if (len < 0) {
					return;
				}
				it.product += " !";
			}
		};
	}
}
