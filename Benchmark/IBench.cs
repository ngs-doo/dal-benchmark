using Revenj.DomainPatterns;
using System.Collections.Generic;
using System.Linq;

namespace Benchmark
{
	public interface IBench<T>
		where T : IAggregateRoot
	{
		void Clean();
		void Analyze();
		IEnumerable<T> SearchAll();
		IEnumerable<T> SearchSubset(int i);
		IQueryable<T> Query();
		T FindSingle(string id);
		IEnumerable<T> FindMany(string[] ids);
		void Insert(IEnumerable<T> values);
		void Update(IEnumerable<T> values);
		void Insert(T value);
		void Update(T value);
		Report<T> Report(int i);
	}

	public class Report<T>
	{
		public T findOne;
		public IEnumerable<T> findMany;
		public T findFirst;
		public T findLast;
		public IEnumerable<T> topFive;
		public IEnumerable<T> lastTen;
	}
}
