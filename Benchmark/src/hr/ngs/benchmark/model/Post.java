package hr.ngs.benchmark.model;

import hr.ngs.benchmark.AggregateRoot;

import java.time.LocalDate;
import java.util.UUID;

public class Post implements AggregateRoot {
	private UUID id;
	private String title;
	private LocalDate created;
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

	public UUID getId() { return id; }
	public void setId(UUID value) { id = value; }

	public String getTitle() { return title; }
	public void setTitle(String value) { title = value; }

	public LocalDate getCreated() { return created; }
	public void setCreated(LocalDate value) { created = value; }

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
