defmodule DocCoffeeLiteWeb.DownloadController do
  use DocCoffeeLiteWeb, :controller

  alias DocCoffeeLite.Translation
  alias DocCoffeeLite.Translation.Export

  def run(conn, %{"project_id" => project_id, "run_id" => run_id}) do
    project = Translation.get_project!(project_id)
    run = Translation.get_translation_run!(run_id)
    
    clean_title = (project.title || "project") |> String.replace(~r/[^a-zA-Z0-9]/, "_")
    lang_suffix = (project.target_lang || "unknown") |> String.downcase()
    filename = "#{clean_title}-translated-#{lang_suffix}.epub"
    path = Path.join(System.tmp_dir!(), "export-#{run.id}.epub")

    case Export.export_epub(run.id, path) do
      :ok -> send_download(conn, {:file, path}, filename: filename)
      {:error, reason} -> send_resp(conn, 500, "Export failed: #{inspect(reason)}")
    end
  end
end
