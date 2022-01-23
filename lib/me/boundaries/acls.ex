defmodule Bonfire.Me.Acls do

  use Arrows
  use Bonfire.Common.Utils
  alias Pointers.ULID
  alias Bonfire.Data.AccessControl.{Acl, Controlled}
  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Me.Users
  import Bonfire.Boundaries.Queries
  import Bonfire.Me.Integration
  import Ecto.Query
  import EctoSparkles
  alias Ecto.Changeset

  def cast(changeset, creator, preset_or_custom) do
    acl = case acls(changeset, creator, preset_or_custom) do
      [] ->
        changeset
        |> Changeset.cast(%{controlled: base_acls(creator, preset_or_custom)}, [])
        |> Changeset.cast_assoc(:controlled)
      custom ->
        Logger.warn("WUP: cast a new custom acl for #{inspect custom} ") # this is slightly tricky because we need to insert the acl with cast_assoc(:acl) while taking the rest of the controlleds from the base maps
        changeset
        |> Changeset.cast(%{controlled: custom}, [])
        |> Changeset.cast_assoc(:controlled, with: &Controlled.changeset/2)
        # |> Changeset.cast_assoc(:acl)
    end
  end

  # when the user picks a preset, this maps to a set of base acls
  defp base_acls(user, preset) do
    acls = case preset do
      "public" -> [:guests_may_see, :locals_may_reply, :i_may_administer]
      "local"  -> [:locals_may_reply, :i_may_administer]
      _        -> [:i_may_administer]
    end
    |> find_acls(user)
  end

  defp find_acls(acls, user) do
    acls =
      acls
      |> Enum.map(&identify/1)
      |> Enum.group_by(&elem(&1, 0))
    globals =
      acls
      |> Map.get(:global, [])
      |> Enum.map(&elem(&1, 1))
    stereo =
      case Map.get(acls, :stereo, []) do
        [] -> []
        stereo ->
          stereo
          |> Enum.map(&elem(&1, 1))
          |> Acls.find_caretaker_stereotypes(user.id, ...)
          |> Enum.map(&(&1.id))
      end
    Enum.map(globals ++ stereo, &(%{acl_id: &1}))
  end

  defp identify(name) do
    defaults = Users.default_acls()
    case defaults[name] do
      nil -> {:global, Acls.get_id!(name)}
      default ->
        case default[:stereotype] do
          nil -> raise RuntimeError, message: "Unstereotyped user acl: #{inspect(name)}"
          stereo -> {:stereo, Acls.get_id!(stereo)}
        end
    end
  end

  defp acls(changeset, creator, preset_or_custom) do
    case custom_grants(changeset, preset_or_custom) do
      [] -> []
      custom_grants when is_list(custom_grants) ->
        acl_id = ULID.generate()

        [
          %{acl: %{acl_id: acl_id, grants: Enum.flat_map(custom_grants, &grant_to(&1, acl_id))}}
          | base_acls(creator, preset_or_custom)
        ]
    end
  end

  defp grant_to(user_etc, acl_id) do
    [:see, :read]
    |> Enum.map(&grant_to(user_etc, acl_id, &1))
  end

  defp grant_to(user_etc, acl_id, verb) do
    %{
      acl_id: acl_id,
      subject_id: user_etc,
      verb_id: Verbs.get_id!(verb),
      value: true
    }
  end

  defp custom_grants(changeset, preset_or_custom) do
    if is_list(preset_or_custom), do: preset_or_custom,
    else: reply_to_grants(changeset, preset_or_custom) ++ mentions_grants(changeset, preset_or_custom)
  end

  defp reply_to_grants(changeset, preset) do
    reply_to_creator = Utils.e(changeset, :changes, :replied, :changes, :replying_to, :created, :creator, nil)

    if reply_to_creator do
      debug(reply_to_creator, "TODO: creators of reply_to should be added to a new ACL")

      case preset do
        "public" ->
          # TODO include all
          [ulid(reply_to_creator)]
        "local" ->
          # TODO include only if local
          if check_local(reply_to_creator), do: [Utils.e(reply_to_creator, :id, nil)],
          else: []
        _ ->
        []
      end
    else
      []
    end
  end

  defp mentions_grants(changeset, preset) do
    mentions = Utils.e(changeset, :changes, :post_content, :changes, :mentions, nil)

    if mentions && mentions !=[] do
      debug(mentions, "TODO: mentions/tags should be added to a new ACL")

      case preset do
        "public" ->
          ulid(mentions)
        "mentions" ->
          ulid(mentions)
        "local" ->
          ( # include only if local
            mentions
            |> Enum.filter(&check_local/1)
            |> ulid()
          )
        _ ->
        []
      end
    else
      []
    end
  end


  ## invariants:

  ## * All a user's ACLs will have the user as an administrator but it
  ##   will be hidden from the user

  def create(attrs \\ %{}, opts) do
    changeset(:create, attrs, opts)
    |> repo().insert()
  end

  def changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, opts, :system), do: Acls.changeset(attrs)
  defp changeset(:create, attrs, opts, %{id: id}) do
    Changeset.cast(%Acl{}, %{caretaker: %{caretaker_id: id}}, [])
    |> Acls.changeset(attrs)
  end

  @doc """
  Lists the ACLs permitted to see.
  """
  def list(opts) do
    list_q(opts)
    |> preload(:named)
    |> repo().many()
  end

  def list_q(opts), do: list_q(Keyword.fetch!(opts, :current_user), opts)
  defp list_q(:system, opts), do: from(acl in Acl, as: :acl)
  defp list_q(%User{}, opts), do: boundarise(list_q(:system, opts), acl.id, opts)

  @doc """
  Lists the ACLs we are the registered caretakers of that we are
  permitted to see. If any are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(%{}=user), do: repo().many(list_my_q(user))

  @doc "query for `list_my`"
  def list_my_q(%{id: user_id}=user) do
    list_q(user)
    |> join(:inner, [acl: acl], caretaker in assoc(acl, :caretaker), as: :caretaker)
    |> where([caretaker: caretaker], caretaker.caretaker_id == ^user_id)
  end

end
