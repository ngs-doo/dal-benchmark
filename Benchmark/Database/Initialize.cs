using System.Configuration;

namespace DALBenchmark
{
	internal static class Initialize
	{
		public static void Postgres()
		{
			var cs = ConfigurationManager.AppSettings["PostgresConnectionString"];
			var dbScript = typeof(Initialize).Assembly.GetManifestResourceStream("DALBenchmark.Database.Postgres.sql");
			using (var conn = new Revenj.DatabasePersistence.Postgres.Npgsql.NpgsqlConnection(cs))
			{
				var com = Revenj.DatabasePersistence.Postgres.PostgresDatabaseQuery.NewCommand(dbScript);
				com.Connection = conn;
				conn.Open();
				com.ExecuteNonQuery();
				conn.Close();
			}
		}
	}
}
