module Simple {
	root Post(id) {
		uuid id;
		string title;
		date created { index; }
		specification FindBy 'it => it.created >= start && it.created <= end' {
			date start;
			date end;
		}
	}

	report FindMultiple {
		guid id;
		guid[] ids;
		date start;
		date end;
		Post findOne 'it => it.id == id';
		List<Post> findMany 'it => ids.Contains(it.id)';
		Post findFirst 'it => it.created >= start' order by created asc;
		Post findLast 'it => it.created <= end' order by created desc;
		List<Post> topFive 'it => it.created >= start && it.created <= end' order by created asc limit 5;
		List<Post> lastTen 'it => it.created >= start && it.created <= end' order by created desc limit 10;
	}
}

server code '
public static partial class ChangeURI {
	public static void Change(Simple.Post a, string uri) {
		a.URI = uri;
	}
}';
