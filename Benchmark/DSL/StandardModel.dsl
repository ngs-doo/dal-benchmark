module Standard {
	mixin Invoice {
		date dueDate;
		decimal total;
		datetime? paid;
		bool canceled;
		long version;
		money tax;
		string(15)? reference;
		timestamp createdAt;
		timestamp modifiedAt;
	}
}
module StandardObjects {
	root Invoice(number) {
		string(20) number;
		has mixin Standard.Invoice;
		List<Item> items;
		index(version);
		index(createdAt);
		specification FindBy 'it => it.version >= start && it.version <= end' {
			int start;
			int end;
		}
	}
	value Item {
		string(100) product;
		decimal cost;
		int quantity;
		decimal(1) taxGroup;
		decimal(2) discount;
	}

	report FindMultiple {
		string(20) id;
		string(20)[] ids;
		long start;
		long end;
		Invoice findOne 'it => it.number == id';
		List<Invoice> findMany 'it => ids.Contains(it.number)';
		Invoice findFirst 'it => it.version >= start' order by createdAt asc;
		Invoice findLast 'it => it.version <= end' order by createdAt desc;
		List<Invoice> topFive 'it => it.version >= start && it.version <= end' order by createdAt asc limit 5;
		List<Invoice> lastTen 'it => it.version >= start && it.version <= end' order by createdAt desc limit 10;
	}
}
module StandardRelations {
	root Invoice(number) {
		string(20) number;
		has mixin Standard.Invoice;
		List<Item> items;
		index(version);
		index(createdAt); //HACK: if index is missing Revenj Report is slow
		specification FindBy 'it => it.version >= start && it.version <= end' {
			int start;
			int end;
		}
	}
	entity Item {
		string(100) product;
		decimal cost;
		int quantity;
		decimal(1) taxGroup;
		decimal(2) discount;
	}

	report FindMultiple {
		string(20) id;
		string(20)[] ids;
		long start;
		long end;
		Invoice findOne 'it => it.number == id';
		List<Invoice> findMany 'it => ids.Contains(it.number)';
		Invoice findFirst 'it => it.version >= start' order by createdAt asc;
		Invoice findLast 'it => it.version <= end' order by createdAt desc;
		List<Invoice> topFive 'it => it.version >= start && it.version <= end' order by createdAt asc limit 5;
		List<Invoice> lastTen 'it => it.version >= start && it.version <= end' order by createdAt desc limit 10;
	}
}

server code '
public static partial class ChangeURI {
	public static void Change(StandardObjects.Invoice a, string uri) {
		a.URI = uri;
	}
	public static void Change(StandardRelations.Invoice a, string uri) {
		a.URI = uri;
	}
}';
