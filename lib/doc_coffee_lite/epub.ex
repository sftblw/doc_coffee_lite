defmodule DocCoffeeLite.Epub do
  @moduledoc """
  Public entrypoints for EPUB handling.
  """

  @mimetype "application/epub+zip"

  @spec mimetype_value() :: String.t()
  def mimetype_value, do: @mimetype

  @spec open(String.t(), String.t()) :: {:ok, DocCoffeeLite.Epub.Session.t()} | {:error, term()}
  def open(epub_path, work_dir), do: DocCoffeeLite.Epub.Session.open(epub_path, work_dir)

  @spec package(DocCoffeeLite.Epub.Session.t()) :: DocCoffeeLite.Epub.Package.t()
  def package(session), do: session.package

  @spec content_paths(DocCoffeeLite.Epub.Session.t()) :: [String.t()]
  def content_paths(session), do: DocCoffeeLite.Epub.Session.content_paths(session)

  @spec read_file(DocCoffeeLite.Epub.Session.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def read_file(session, path), do: DocCoffeeLite.Epub.Session.read_file(session, path)

  @spec update_file(DocCoffeeLite.Epub.Session.t(), String.t(), iodata()) ::
          {:ok, DocCoffeeLite.Epub.Session.t()} | {:error, term()}
  def update_file(session, path, content) do
    DocCoffeeLite.Epub.Session.update_file(session, path, content)
  end

  @spec build(DocCoffeeLite.Epub.Session.t(), String.t()) :: :ok | {:error, term()}
  def build(session, output_path), do: DocCoffeeLite.Epub.Session.build(session, output_path)
end
