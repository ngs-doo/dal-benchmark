package hr.ngs.benchmark;

import java.util.List;

public interface IBench<T extends IAggregateRoot> {
	void clean();
	void analyze();
	List<T> searchAll();
	List<T> searchSubset(int i);
	//IQueryable<T> query();
	T findSingle(String id);
	List<T> findMany(String[] ids);
	void insert(Iterable<T> values);
	void update(Iterable<T> values);
	void insert(T value);
	void update(T value);
	Report<T> report(int i);
}
