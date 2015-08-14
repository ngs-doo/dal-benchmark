package hr.ngs.benchmark;

import org.revenj.patterns.AggregateRoot;

import java.io.IOException;
import java.util.Collection;
import java.util.List;

public interface Bench<T extends AggregateRoot> {

	void clean() throws IOException;

	void analyze() throws IOException;

	List<T> searchAll() throws IOException;

	List<T> searchSubset(int i) throws IOException;

	List<T> queryAll() throws IOException;

	List<T> querySubset(int i) throws IOException;

	T findSingle(String id) throws IOException;

	List<T> findMany(String[] ids) throws IOException;

	void insert(Collection<T> values) throws IOException;

	void update(Collection<T> values) throws IOException;

	void insert(T value) throws IOException;

	void update(T value) throws IOException;

	Report<T> report(int i) throws IOException;
}
