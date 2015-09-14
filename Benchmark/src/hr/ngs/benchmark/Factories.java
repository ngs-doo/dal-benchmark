package hr.ngs.benchmark;

import hr.ngs.benchmark.model.Invoice;
import hr.ngs.benchmark.model.InvoiceItem;
import hr.ngs.benchmark.model.Post;

import java.math.BigDecimal;
import java.net.URI;
import java.time.*;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public abstract class Factories {

	public static final LocalDate TODAY = LocalDate.now();
	public static final OffsetDateTime NOW = OffsetDateTime.now(ZoneOffset.UTC);

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

	public static void newSimple(hr.ngs.benchmark.Simple.Post post, int i) {
		post.setId(Factories.GetUUID(i));
		post.setTitle("title " + i);
		post.setCreated(Factories.TODAY.plusDays(i));
	}

	public static ModifyObject<Post> updateSimple() {
		return (value, i) -> value.setTitle(value.getTitle() + "!");
	}

	public static void updateSimple(hr.ngs.benchmark.Simple.Post post, int i) {
		post.setTitle(post.getTitle() + "!");
	}

	public static ModifyObject<Invoice> newStandard() {
		return (inv, i) -> {
			inv.setNumber(Integer.toString(i));
			inv.setTotal(BigDecimal.valueOf(100 + i));
			inv.setDueDate(TODAY.plusDays(i / 2));
			inv.setPaid(i % 3 == 0 ? TODAY.plusDays(i).atStartOfDay().atOffset(ZoneOffset.UTC) : null);
			inv.setReference(i % 7 == 0 ? Integer.toString(i) : null);
			inv.setTax(BigDecimal.valueOf(15 + i % 10).setScale(2));
			inv.setVersion(i);
			inv.setCanceled(i % 5 == 0);
			for (int j = 0; j < i % 10; j++) {
				InvoiceItem item = new InvoiceItem();
				item.setProduct("prod " + i + " - " + j);
				item.setCost(BigDecimal.valueOf((i + j * j) / 100));
				item.setDiscount(BigDecimal.valueOf(i % 3 == 0 ? i % 10 + 5 : 0));
				item.setQuantity(i / 100 + j / 2 + 1);
				item.setTaxGroup(BigDecimal.valueOf(5 + i % 20));
				inv.addItem(item);
			}
		};
	}

	public static void newStandard(hr.ngs.benchmark.StandardObjects.Invoice inv, int i) {
		inv.setNumber(Integer.toString(i));
		inv.setTotal(BigDecimal.valueOf(100 + i));
		inv.setDueDate(Factories.TODAY.plusDays(i / 2));
		inv.setPaid(i % 3 == 0 ? Factories.TODAY.plusDays(i).atStartOfDay().atOffset(ZoneOffset.UTC) : null);
		inv.setReference(i % 7 == 0 ? Integer.toString(i) : null);
		inv.setTax(BigDecimal.valueOf(15 + i % 10));
		inv.setVersion(i);
		inv.setCanceled(i % 5 == 0);
		for (int j = 0; j < i % 10; j++) {
			inv.getItems().add(
					new hr.ngs.benchmark.StandardObjects.Item()
							.setProduct("prod " + i + " - " + j)
							.setCost(BigDecimal.valueOf((i + j * j) / 100))
							.setDiscount(BigDecimal.valueOf(i % 3 == 0 ? i % 10 + 5 : 0))
							.setQuantity(i / 100 + j / 2 + 1)
							.setTaxGroup(BigDecimal.valueOf(5 + i % 20)));
		}
	}

	public static void newStandard(hr.ngs.benchmark.StandardRelations.Invoice inv, int i) {
		inv.setNumber(Integer.toString(i));
		inv.setTotal(BigDecimal.valueOf(100 + i));
		inv.setDueDate(Factories.TODAY.plusDays(i / 2));
		inv.setPaid(i % 3 == 0 ? Factories.TODAY.plusDays(i).atStartOfDay().atOffset(ZoneOffset.UTC) : null);
		inv.setReference(i % 7 == 0 ? Integer.toString(i) : null);
		inv.setTax(BigDecimal.valueOf(15 + i % 10));
		inv.setVersion(i);
		inv.setCanceled(i % 5 == 0);
		for (int j = 0; j < i % 10; j++) {
			inv.getItems().add(
					new hr.ngs.benchmark.StandardRelations.Item()
							.setProduct("prod " + i + " - " + j)
							.setCost(BigDecimal.valueOf((i + j * j) / 100))
							.setDiscount(BigDecimal.valueOf(i % 3 == 0 ? i % 10 + 5 : 0))
							.setQuantity(i / 100 + j / 2 + 1)
							.setTaxGroup(BigDecimal.valueOf(5 + i % 20)));
		}
	}

	public static ModifyObject<Invoice> updateStandard() {
		return (invoice, i) -> {
			invoice.setPaid(NOW.plusNanos(i * 1000));
			int len = invoice.getItems().size() / 3;
			for (InvoiceItem it : invoice.getItems()) {
				len--;
				if (len < 0) {
					return;
				}
				it.setProduct(it.getProduct() + " !");
			}
		};
	}

	public static void updateStandard(hr.ngs.benchmark.StandardObjects.Invoice inv, int i) {
		inv.setPaid(Factories.NOW.plusNanos(i * 1000));
		int len = inv.getItems().size() / 3;
		for (hr.ngs.benchmark.StandardObjects.Item it : inv.getItems()) {
			len--;
			if (len < 0) {
				return;
			}
			it.setProduct(it.getProduct() + " !");
		}
	}

	public static void updateStandard(hr.ngs.benchmark.StandardRelations.Invoice inv, int i) {
		inv.setPaid(Factories.NOW.plusNanos(i * 1000));
		int len = inv.getItems().size() / 3;
		for (hr.ngs.benchmark.StandardRelations.Item it : inv.getItems()) {
			len--;
			if (len < 0) {
				return;
			}
			it.setProduct(it.getProduct() + " !");
		}
	}

	private static void fillDict(int i, Map<String, String> dict) {
		for (int j = 0; j < i / 3 % 10; j++) {
			dict.put("key" + j, "value " + i);
		}
	}

	public static void newComplex(hr.ngs.benchmark.ComplexObjects.BankScrape scrape, int i) {
		scrape.setId(i);
		scrape.setWebsite(URI.create("https://dsl-platform.com/benchmark/" + i));
		List<String> tags = IntStream.range(i % 20, (i % 20) + (i % 6)).mapToObj(it -> "tag" + it).collect(Collectors.toList());
		scrape.setTags(new HashSet<>(tags));
		scrape.setInfo(new HashMap<>());
		fillDict(i, scrape.getInfo());
		scrape.setExternalId(i % 3 != 0 ? Integer.toString(i) : null);
		scrape.setRanking(i);
		scrape.setCreatedAt(Factories.NOW.plusMinutes(i));
		for (int j = 0; j < i % 10; j++) {
			hr.ngs.benchmark.ComplexObjects.Account acc = new hr.ngs.benchmark.ComplexObjects.Account();
			acc.setBalance(BigDecimal.valueOf(55.0 + i / (j + 1) - j * j));
			acc.setName( "acc " + i + " - " + j);
			acc.setNumber(i + "-" + j);
			acc.setNotes("some notes " + String.format("%" + (j * 10 + 1) + "d", i).replace(' ', 'x'));
			scrape.getAccounts().add(acc);
			for (int k = 0; k < (i + j) % 300; k++) {
				hr.ngs.benchmark.ComplexObjects.Transaction tran = new hr.ngs.benchmark.ComplexObjects.Transaction();
				tran.setAmount(BigDecimal.valueOf(i / (j + k + 100)));
				tran.setCurrency(hr.ngs.benchmark.Complex.Currency.values()[k % 3]);
				tran.setDate(Factories.TODAY.plusDays(i + j + k));
				tran.setDescription("transaction " + i + " at " + k);
				acc.getTransactions().add(tran);
			}
		}
	}

	public static void newComplex(hr.ngs.benchmark.ComplexRelations.BankScrape scrape, int i) {
		scrape.setId(i);
		scrape.setWebsite(URI.create("https://dsl-platform.com/benchmark/" + i));
		List<String> tags = IntStream.range(i % 20, (i % 20) + (i % 6)).mapToObj(it -> "tag" + it).collect(Collectors.toList());
		scrape.setTags(new HashSet<>(tags));
		scrape.setInfo(new HashMap<>());
		fillDict(i, scrape.getInfo());
		scrape.setExternalId(i % 3 != 0 ? Integer.toString(i) : null);
		scrape.setRanking(i);
		scrape.setCreatedAt(Factories.NOW.plusMinutes(i));
		for (int j = 0; j < i % 10; j++) {
			hr.ngs.benchmark.ComplexRelations.Account acc = new hr.ngs.benchmark.ComplexRelations.Account();
			acc.setBalance(BigDecimal.valueOf(55.0 + i / (j + 1) - j * j));
			acc.setName( "acc " + i + " - " + j);
			acc.setNumber(i + "-" + j);
			acc.setNotes("some notes " + String.format("%" + (j * 10 + 1) + "d", i).replace(' ', 'x'));
			scrape.getAccounts().add(acc);
			for (int k = 0; k < (i + j) % 300; k++) {
				hr.ngs.benchmark.ComplexRelations.Transaction tran = new hr.ngs.benchmark.ComplexRelations.Transaction();
				tran.setAmount(BigDecimal.valueOf(i / (j + k + 100)));
				tran.setCurrency(hr.ngs.benchmark.Complex.Currency.values()[k % 3]);
				tran.setDate(Factories.TODAY.plusDays(i + j + k));
				tran.setDescription("transaction " + i + " at " + k);
				acc.getTransactions().add(tran);
			}
		}
	}

	public static void updateComplex(hr.ngs.benchmark.ComplexObjects.BankScrape scrape, int i) {
		scrape.setAt(Factories.NOW.plusNanos(i * 1000));
		int lenAcc = scrape.getAccounts().size() / 3;
		for (hr.ngs.benchmark.ComplexObjects.Account acc : scrape.getAccounts()) {
			lenAcc--;
			if (lenAcc < 0)
				return;
			acc.setBalance(acc.getBalance().add(BigDecimal.valueOf(10)));
			int lenTran = acc.getTransactions().size() / 5;
			for (hr.ngs.benchmark.ComplexObjects.Transaction tran : acc.getTransactions()) {
				lenTran--;
				if (lenTran < 0)
					break;
				tran.setAmount(tran.getAmount().add(BigDecimal.valueOf(5)));
			}
		}
	}

	public static void updateComplex(hr.ngs.benchmark.ComplexRelations.BankScrape scrape, int i) {
		scrape.setAt(Factories.NOW.plusNanos(i * 1000));
		int lenAcc = scrape.getAccounts().size() / 3;
		for (hr.ngs.benchmark.ComplexRelations.Account acc : scrape.getAccounts()) {
			lenAcc--;
			if (lenAcc < 0)
				return;
			acc.setBalance(acc.getBalance().add(BigDecimal.valueOf(10)));
			int lenTran = acc.getTransactions().size() / 5;
			for (hr.ngs.benchmark.ComplexRelations.Transaction tran : acc.getTransactions()) {
				lenTran--;
				if (lenTran < 0)
					break;
				tran.setAmount(tran.getAmount().add(BigDecimal.valueOf(5)));
			}
		}
	}
}
