package hr.ngs.benchmark;

import org.revenj.patterns.AggregateRoot;

import java.io.IOException;
import java.util.Collection;
import java.util.List;
import java.util.stream.Stream;

public interface Bench<T extends AggregateRoot> {
	void clean() throws IOException;
	void analyze() throws IOException;
	List<T> searchAll();
	List<T> searchSubset(int i);
	Stream<T> stream() throws IOException;
	T findSingle(String id);
	List<T> findMany(String[] ids);
	void insert(Collection<T> values) throws IOException;
	void update(Collection<T> values) throws IOException;
	void insert(T value) throws IOException;
	void update(T value) throws IOException;
	Report<T> report(int i);
}
