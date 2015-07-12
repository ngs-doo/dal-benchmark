package hr.ngs.benchmark;

import java.util.ArrayList;
import java.util.List;

public class Report<T> {
	public T findOne;
	public List<T> findMany = new ArrayList<>();
	public T findFirst;
	public T findLast;
	public List<T> topFive = new ArrayList<>();
	public List<T> lastTen = new ArrayList<>();
}

