package hr.ngs.benchmark;

import hr.ngs.benchmark.model.Invoice;
import hr.ngs.benchmark.model.Post;
import org.joda.time.DateTime;
import org.joda.time.LocalDate;

import java.math.BigDecimal;
import java.util.UUID;

public abstract class Factories {

	public static final LocalDate TODAY = LocalDate.now();
	public static final DateTime NOW = DateTime.now();

	public static UUID GetUUID(int i) {
		return new UUID(i, 0);
	}

	public static ModifyObject<Post> newSimple() {
		return new ModifyObject<Post>() {
			@Override
			public void run(Post value, int i) {
				value.id = GetUUID(i);
				value.title = "title " + i;
				value.created = TODAY.plusDays(i);
			}
		};
	}

	public static ModifyObject<Post> updateSimple() {
		return new ModifyObject<Post>() {
			@Override
			public void run(Post value, int i) {
				value.title = value.title + "!";
			}
		};
	}

	public static ModifyObject<Invoice> newStandard() {
		return new ModifyObject<Invoice>() {
			@Override
			public void run(Invoice inv, int i) {
				inv.number = Integer.toString(i);
				inv.total = BigDecimal.valueOf(100 + i);
				inv.dueDate = TODAY.plusDays(i / 2);
				inv.paid = i % 3 == 0 ? TODAY.plusDays(i).toDateTimeAtCurrentTime() : null;
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
			}
		};
	}

	public static ModifyObject<Invoice> updateStandard() {
		return new ModifyObject<Invoice>() {
			@Override
			public void run(Invoice invoice, int i) {
				invoice.paid = NOW.plusMillis(i);
				int len = invoice.items.size() / 3;
				for(Invoice.Item it : invoice.items) {
					len--;
					if (len < 0) {
						return;
					}
					it.product += " !";
				}
			}
		};
	}
}
