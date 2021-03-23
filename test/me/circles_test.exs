defmodule Bonfire.Me.CirclesTest do

  use Bonfire.DataCase, async: true
  alias Bonfire.Me.Fake
  alias Bonfire.Me.Users
  alias Bonfire.Me.Users.Circles
  alias Bonfire.Repo

  test "listing instance-wide circles (which I am permitted to see) works" do
    user = fake_user!()

    assert circles = Circles.list_visible(user)
    assert length(circles) == Bonfire.Boundaries.Circles.circles() |> Map.keys() |> length()

  end

  test "creation works" do
    user = fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)
    assert name == circle.named.name
    assert user.id == circle.caretaker.caretaker_id

  end

  test "listing my circles works" do
    user = fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)

    assert circles = Circles.list_my(user)
    assert is_list(circles)

    my_circle = List.first(circles)
    my_circle = Repo.preload(my_circle, [:named, :caretaker])

    assert name == my_circle.named.name
    assert user.id == my_circle.caretaker.caretaker_id

  end

  test "cannot list someone else's circles" do
    me = fake_user!()
    user = fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)

    assert circles = Circles.list_my(me)
    assert length(circles) == 0

  end

  test "cannot list circles which I am not permitted to see" do
    me = fake_user!()
    user = fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)

    assert circles = Circles.list_visible(me)
    # IO.inspect(circles)
    assert length(circles) == Bonfire.Boundaries.Circles.circles() |> Map.keys() |> length()

  end

end
