package hr.ngs.benchmark;

import java.util.Collection;
import java.util.List;
import java.util.stream.Stream;

public interface Bench<T extends AggregateRoot> {
	void clean();
	void analyze();
	List<T> searchAll();
	List<T> searchSubset(int i);
	Stream<T> stream();
	T findSingle(String id);
	List<T> findMany(String[] ids);
	void insert(Collection<T> values);
	void update(Collection<T> values);
	void insert(T value);
	void update(T value);
	Report<T> report(int i);
}