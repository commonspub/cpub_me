defmodule Bonfire.Me.Web.SettingsLive do
  use Bonfire.Web, {:live_view, [layout: {Bonfire.Web.LayoutView, "settings_template.html"}]}

  alias Bonfire.Web.LivePlugs

  def mount(params, session, socket) do
    LivePlugs.live_plug params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      LivePlugs.StaticChanged,
      LivePlugs.Csrf,
      &mounted/3,
    ]
  end

  defp mounted(_params, _session, socket),
    do: {:ok,
      socket
      |> assign(
        page_title: "Settings",
        selected_tab: "user",
        page: "Settings",
        trigger_submit: false,
        uploaded_files: []
      )
      |> allow_upload(:icon,
        accept: ~w(.jpg .jpeg .png .gif),
        max_file_size: 2_000_000, # make configurable, expecially once we have resizing
        max_entries: 1,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> allow_upload(:image,
        accept: ~w(.jpg .jpeg .png .gif .svg .tiff),
        max_file_size: 4_000_000, # make configurable, expecially once we have resizing
        max_entries: 1,
        auto_upload: true,
        progress: &handle_progress/3
      )
    }

  defp handle_progress(:icon, entry, socket) do

    user = e(socket, :assigns, :current_user, nil)

    if user && entry.done? do
      with {:ok, uploaded_media} <-
        consume_uploaded_entry(socket, entry, fn %{path: path} = meta ->
          # IO.inspect(meta)
          Bonfire.Files.IconUploader.upload(user, path)
        end),
        Bonfire.Me.Users.update(user, %{"profile"=> %{"icon"=> uploaded_media, "icon_id"=> uploaded_media.id}}) do
          # IO.inspect(uploaded_media)
          {:noreply, socket
          |> assign(current_user: deep_merge(user, %{profile: %{icon: uploaded_media}}))
          |> put_flash(:info, "Avatar changed!")}
        end

    else
      {:noreply, socket}
    end
  end

  defp handle_progress(:image, entry, socket) do
    user = e(socket, :assigns, :current_user, nil)

    if user && entry.done? do
      with {:ok, uploaded_media} <-
        consume_uploaded_entry(socket, entry, fn %{path: path} = meta ->
          # IO.inspect(meta)
          Bonfire.Files.ImageUploader.upload(user, path)
        end),
        Bonfire.Me.Users.update(user, %{"profile"=> %{"image"=> uploaded_media, "image_id"=> uploaded_media.id}}) do
          # IO.inspect(uploaded_media)
          {:noreply,
          socket
          |> assign(current_user: deep_merge(user, %{profile: %{image: uploaded_media}}))
          |> put_flash(:info, "Background image changed!")}
        end

    else
      {:noreply, socket}
    end
  end

  def handle_params(%{"tab" => tab, "id" => id}, _url, socket) do
    {:noreply, assign(socket, selected_tab: tab, id: id)}
  end

  def handle_params(%{"tab" => tab}, _url, socket) do
    {:noreply, assign(socket, selected_tab: tab)}
  end

  def handle_params(_, _url, socket) do
    {:noreply, socket}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(action, attrs, socket), do: Bonfire.Web.LiveHandler.handle_event(action, attrs, socket, __MODULE__)

end
