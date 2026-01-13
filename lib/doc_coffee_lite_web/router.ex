defmodule DocCoffeeLiteWeb.Router do
  use DocCoffeeLiteWeb, :router
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DocCoffeeLiteWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DocCoffeeLiteWeb do
    pipe_through :browser

    oban_dashboard "/oban"
    live "/", HomeLive
    live "/projects", ProjectsLive
    live "/projects/:project_id", ProjectLive
    live "/projects/:project_id/glossary", GlossaryLive
    live "/projects/:project_id/llm", ProjectLlmLive
    live "/projects/:project_id/runs/:run_id/groups/:group_id/blocks", BlockEditLive
    live "/settings/llm", UserLlmLive
    get "/projects/:project_id/runs/:run_id/download", DownloadController, :run
  end

  # Other scopes may use custom stacks.
  # scope "/api", DocCoffeeLiteWeb do
  #   pipe_through :api
  # end
end
