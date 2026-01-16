defmodule DocCoffeeLiteWeb.ExportController do
  use DocCoffeeLiteWeb, :controller
  alias DocCoffeeLite.Translation.ImportExport

  def export(conn, %{"project_id" => project_id}) do
    case ImportExport.export_project(project_id) do
      {:ok, zip_path} ->
        filename = Path.basename(zip_path)

        conn
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> put_resp_content_type("application/zip")
        |> send_file(200, zip_path)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Export failed: #{inspect(reason)}")
        |> redirect(to: ~p"/projects/#{project_id}")
    end
  end
end
