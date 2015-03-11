module Complex {
	enum Currency {
		EUR;
		USD;
		Other;
	}
	mixin BankScrape {
		url website;
		timestamp at;
		map info;
		string(50)? externalId;
		int ranking;
		set<string(10)> tags;
		timestamp createdAt;
	}	
}
module ComplexObjects {
	root BankScrape(id) {
		int id;
		has mixin Complex.BankScrape;
		List<Account> accounts;
		index(createdAt);
		specification FindBy 'it => it.createdAt >= start && it.createdAt <= end' {
			timestamp start;
			timestamp end;
		}
	}
	value Account {
		money balance;
		string(40) number;
		string(100) name;
		string(800) notes;
		List<Transaction> transactions;
	}
	value Transaction {
		date date;
		string(200) description;
		Complex.Currency currency;
		money amount;
	}

	report FindMultiple {
		int id;
		int[] ids;
		timestamp start;
		timestamp end;
		BankScrape findOne 'it => it.id == id';
		BankScrape[] findMany 'it => ids.Contains(it.id)';
		BankScrape findFirst 'it => it.createdAt >= start' order by createdAt asc;
		BankScrape findLast 'it => it.createdAt <= end' order by createdAt desc;
		BankScrape[] topFive 'it => it.createdAt >= start && it.createdAt <= end' order by createdAt asc limit 5;
		BankScrape[] lastTen 'it => it.createdAt >= start && it.createdAt <= end' order by createdAt desc limit 10;
	}
}

module ComplexRelations {
	root BankScrape(id) {
		int id;
		has mixin Complex.BankScrape;
		List<Account> accounts;
		index(createdAt);
		specification FindBy 'it => it.createdAt >= start && it.createdAt <= end' {
			timestamp start;
			timestamp end;
		}
	}
	entity Account {
		money balance;
		string(40) number;
		string(100) name;
		string(800) notes;
		List<Transaction> transactions;
	}
	entity Transaction {
		date date;
		string(200) description;
		Complex.Currency currency;
		money amount;
	}

	report FindMultiple {
		int id;
		int[] ids;
		timestamp start;
		timestamp end;
		BankScrape findOne 'it => it.id == id';
		BankScrape[] findMany 'it => ids.Contains(it.id)';
		BankScrape findFirst 'it => it.createdAt >= start' order by createdAt asc;
		BankScrape findLast 'it => it.createdAt <= end' order by createdAt desc;
		BankScrape[] topFive 'it => it.createdAt >= start && it.createdAt <= end' order by createdAt asc limit 5;
		BankScrape[] lastTen 'it => it.createdAt >= start && it.createdAt <= end' order by createdAt desc limit 10;
	}
}

server code '
public static partial class ChangeURI {
	public static void Change(ComplexObjects.BankScrape a, string uri) {
		a.URI = uri;
	}
	public static void Change(ComplexRelations.BankScrape a, string uri) {
		a.URI = uri;
	}
}';