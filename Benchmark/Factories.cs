using System;
using System.Collections.Generic;
using System.Linq;

namespace Benchmark
{
	internal static class Factories
	{
		public static DateTime Now = DateTime.Now;
		public static DateTime Today = DateTime.Today;

		private static byte[] GuidBytes = new byte[8];

		public static Guid GetGuid(int i)
		{
			return new Guid(i, (short)i, (byte)i, GuidBytes);
		}

		public static void NewSimple(dynamic post, int i)
		{
			post.id = GetGuid(i);
			post.title = "title " + i;
			post.created = Today.AddDays(i);
		}
		public static void UpdateSimple(dynamic post, int i)
		{
			post.title = post.title + "!";
		}

		public static void NewStandard<TItem>(dynamic inv, int i) where TItem : new()
		{
			inv.number = i.ToString();
			inv.total = 100 + i;
			inv.dueDate = Today.AddDays(i / 2);
			inv.paid = i % 3 == 0 ? (DateTime?)Today.AddDays(i) : null;
			inv.reference = i % 7 == 0 ? i.ToString() : null;
			inv.tax = 15 + i % 10;
			inv.version = i;
			inv.canceled = i % 5 == 0;
			for (int j = 0; j < i % 10; j++)
			{
				dynamic item = new TItem();
				item.product = "prod " + i + " - " + j;
				item.cost = (i + j * j) / 100m;
				item.discount = i % 3 == 0 ? i % 10 + 5 : 0;
				item.quantity = i / 100 + j / 2 + 1;
				item.taxGroup = 5 + i % 20;
				inv.items.Add(item);
			}
		}
		public static void UpdateStandard(dynamic invoice, int i)
		{
			invoice.paid = Now.AddMilliseconds(i);
			var len = invoice.items.Count / 3;
			foreach (var it in invoice.items)
			{
				len--;
				if (len < 0)
					return;
				it.product += " !";
			}
		}

		private static void FillDict(int i, Dictionary<string, string> dict)
		{
			for (int j = 0; j < i / 3 % 10; j++)
				dict["key" + j] = "value " + i;
		}

		public static void NewComplex<TAccount, TTransaciton>(dynamic scrape, int i)
			where TAccount : new()
			where TTransaciton : new()
		{
			scrape.id = i;
			bool failed;
			try
			{
				scrape.website = new Uri("https://dsl-platform.com/benchmark/" + i);
				scrape.tags = new HashSet<string>(Enumerable.Range(i % 20, i % 6).Select(it => "tag" + it));
				scrape.info = new Dictionary<string, string>();
				FillDict(i, scrape.info);
				failed = false;
			}
			catch
			{
				failed = true;
				scrape.website = "https://dsl-platform.com/benchmark/" + i;
			}
			scrape.externalId = i % 3 != 0 ? i.ToString() : null;
			scrape.ranking = i;
			scrape.createdAt = Now.AddMinutes(i);
			for (int j = 0; j < i % 10; j++)
			{
				dynamic acc = new TAccount();
				acc.balance = 55m + i / (j + 1) - j * j;
				acc.name = "acc " + i + " - " + j;
				acc.number = i + "-" + j;
				acc.notes = "some notes " + (i.ToString()).PadLeft(j * 10, 'x');
				scrape.accounts.Add(acc);
				for (int k = 0; k < (i + j) % 300; k++)
				{
					dynamic tran = new TTransaciton();
					tran.amount = i / (j + k + 100);
					if (!failed)
						tran.currency = (Complex.Currency)(k % 3);
					tran.date = Today.AddDays(i + j + k);
					tran.description = "transaction " + i + " at " + k;
					acc.transactions.Add(tran);
				}
			}
		}
		public static void UpdateComplex(dynamic scrape, int i)
		{
			scrape.at = Now.AddMilliseconds(i);
			var lenAcc = scrape.accounts.Count / 3;
			foreach (var acc in scrape.accounts)
			{
				lenAcc--;
				if (lenAcc < 0)
					return;
				acc.balance += 10;
				var lenTran = acc.transactions.Count / 5;
				foreach (var tran in acc.transactions)
				{
					lenTran--;
					if (lenTran < 0)
						break;
					tran.amount += 5;
				}
			}
		}
	}
}
