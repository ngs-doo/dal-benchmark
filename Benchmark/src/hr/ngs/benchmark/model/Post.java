package hr.ngs.benchmark.model;

import hr.ngs.benchmark.IAggregateRoot;
import org.joda.time.LocalDate;

import java.util.UUID;

public class Post implements IAggregateRoot {
	public UUID id;
	public String title;
	public LocalDate created;
	private String URI;

	public Post() {
		this.id = UUID.randomUUID();
		this.title = "";
		this.created = LocalDate.now();
	}

	public Post(UUID id, String title, LocalDate created) {
		this.id = id;
		this.title = title;
		this.created = created;
	}

	@Override
	public String getURI() {
		if (URI == null) {
			URI = id.toString();
		}
		return URI;
	}

	@Override
	public int hashCode() {
		return id.hashCode();
	}

	@Override
	public boolean equals(Object other) {
		if (other == null || !(other instanceof Post)) {
			return false;
		}
		Post value = (Post)other;
		return value.id.equals(this.id)
				&& value.title.equals(this.title)
				&& value.created.equals(this.created);
	}
}
