using Revenj.DomainPatterns;
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

		public static Simple.Post CreateNewSimple(int i)
		{
			return new Simple.Post { id = GetGuid(i), title = "title " + i, created = Today.AddDays(i) };
		}
		public static void Update(Simple.Post post, int i)
		{
			post.title = post.title + "!";
		}
		public static ISpecification<Simple.Post> GetSimpleFilter(int i)
		{
			return new Simple.Post.FindBy(Today.AddDays(i), Today.AddDays(i + 10));
		}

		public static StandardObjects.Invoice CreateSO(int i)
		{
			var inv = new StandardObjects.Invoice
			{
				number = i.ToString(),
				total = 100 + i,
				dueDate = Today.AddDays(i / 2),
				paid = i % 3 == 0 ? (DateTime?)Today.AddDays(i) : null,
				reference = i % 7 == 0 ? i.ToString() : null,
				tax = 15 + i % 10,
				version = i,
				canceled = i % 5 == 0
			};
			for (int j = 0; j < i % 10; j++)
				inv.items.Add(new StandardObjects.Item
				{
					product = "prod " + i + " - " + j,
					cost = (i + j * j) / 100m,
					discount = i % 3 == 0 ? i % 10 + 5 : 0,
					quantity = i / 100 + j / 2 + 1,
					taxGroup = 5 + i % 20
				});
			return inv;
		}
		public static void Update(StandardObjects.Invoice invoice, int i)
		{
			invoice.paid = Now.AddMilliseconds(i);
			for (int j = 0; j < invoice.items.Count / 3; j++)
				invoice.items[j].product += " !";
		}
		public static ISpecification<StandardObjects.Invoice> GetSOFilter(int i)
		{
			return new StandardObjects.Invoice.FindBy(i, i + 10);
		}

		public static StandardRelations.Invoice CreateSR(int i)
		{
			var inv = new StandardRelations.Invoice
			{
				number = i.ToString(),
				total = 100 + i,
				dueDate = Today.AddDays(i / 2),
				paid = i % 3 == 0 ? (DateTime?)Today.AddDays(i) : null,
				reference = i % 7 == 0 ? i.ToString() : null,
				tax = 15 + i % 10,
				version = i,
				canceled = i % 5 == 0
			};
			for (int j = 0; j < i % 10; j++)
				inv.items.Add(new StandardRelations.Item
				{
					product = "prod " + i + " - " + j,
					cost = (i + j * j) / 100m,
					discount = i % 3 == 0 ? i % 10 + 5 : 0,
					quantity = i / 100 + j / 2 + 1,
					taxGroup = 5 + i % 20
				});
			return inv;
		}
		public static void Update(StandardRelations.Invoice invoice, int i)
		{
			invoice.paid = Now.AddMilliseconds(i);
			for (int j = 0; j < invoice.items.Count / 3; j++)
				invoice.items[j].product += " !";
		}
		public static ISpecification<StandardRelations.Invoice> GetSRFilter(int i)
		{
			return new StandardRelations.Invoice.FindBy(i, i + 10);
		}

		private static void FillDict(int i, Dictionary<string, string> dict)
		{
			// allow null properties
			if (dict == null)
				return ;
			for (int j = 0; j < i / 3 % 10; j++)
				dict["key" + j] = "value " + i;
		}

		public static ComplexObjects.BankScrape CreateCO(int i)
		{
			var scrape = new ComplexObjects.BankScrape
			{
				id = i,
				website = new Uri("https://dsl-platform.com/benchmark/" + i),
				externalId = i % 3 != 0 ? i.ToString() : null,
				ranking = i,
				tags = new HashSet<string>(Enumerable.Range(i % 20, i % 6).Select(it => "tag" + it)),
				createdAt = Now.AddMinutes(i)
			};
			FillDict(i, scrape.info);
			for (int j = 0; j < i % 10; j++)
			{
				var acc = new ComplexObjects.Account
				{
					balance = 55m + i / (j + 1) - j * j,
					name = "acc " + i + " - " + j,
					number = i + "-" + j,
					notes = "some notes " + (i.ToString()).PadLeft(j * 10, 'x')
				};
				scrape.accounts.Add(acc);
				for (int k = 0; k < (i + j) % 300; k++)
				{
					var tran = new ComplexObjects.Transaction
					{
						amount = i / (j + k + 100),
						currency = (Complex.Currency)(k % 3),
						date = Today.AddDays(i + j + k),
						description = "transaction " + i + " at " + k
					};
					acc.transactions.Add(tran);
				}
			}
			return scrape;
		}
		public static void Update(ComplexObjects.BankScrape scrape, int i)
		{
			scrape.at = Now.AddMilliseconds(i);
			for (int j = 0; j < scrape.accounts.Count / 3; j++)
			{
				var acc = scrape.accounts[j];
				acc.balance += 10;
				for (int k = 0; k < acc.transactions.Count / 5; k++)
				{
					var tran = acc.transactions[k];
					tran.amount += 5;
				}
			}
		}
		public static ISpecification<ComplexObjects.BankScrape> GetCOFilter(int i)
		{
			return new ComplexObjects.BankScrape.FindBy(Now.AddMinutes(i), Now.AddMinutes(i + 10));
		}

		public static ComplexRelations.BankScrape CreateCR(int i)
		{
			var scrape = new ComplexRelations.BankScrape
			{
				id = i,
				website = new Uri("https://dsl-platform.com/benchmark/" + i),
				externalId = i % 3 != 0 ? i.ToString() : null,
				ranking = i,
				tags = new HashSet<string>(Enumerable.Range(i % 20, i % 6).Select(it => "tag" + it)),
				createdAt = Now.AddMinutes(i)
			};
			FillDict(i, scrape.info);
			for (int j = 0; j < i % 10; j++)
			{
				var acc = new ComplexRelations.Account
				{
					balance = 55m + i / (j + 1) - j * j,
					name = "acc " + i + " - " + j,
					number = i + "-" + j,
					notes = "some notes " + (i.ToString()).PadLeft(j * 10, 'x')
				};
				scrape.accounts.Add(acc);
				for (int k = 0; k < (i + j) % 300; k++)
				{
					var tran = new ComplexRelations.Transaction
					{
						amount = i / (j + k + 100),
						currency = (Complex.Currency)(k % 3),
						date = Today.AddDays(i + j + k),
						description = "transaction " + i + " at " + k
					};
					acc.transactions.Add(tran);
				}
			}
			return scrape;
		}
		public static void Update(ComplexRelations.BankScrape scrape, int i)
		{
			scrape.at = Now.AddMilliseconds(i);
			for (int j = 0; j < scrape.accounts.Count / 3; j++)
			{
				var acc = scrape.accounts[j];
				acc.balance += 10;
				for (int k = 0; k < acc.transactions.Count / 5; k++)
				{
					var tran = acc.transactions[k];
					tran.amount += 5;
				}
			}
		}
		public static ISpecification<ComplexRelations.BankScrape> GetCRFilter(int i)
		{
			return new ComplexRelations.BankScrape.FindBy(Now.AddMinutes(i), Now.AddMinutes(i + 10));
		}
	}
}
