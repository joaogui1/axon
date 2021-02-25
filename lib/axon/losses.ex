defmodule Axon.Losses do
  @moduledoc """
  Loss functions.

  Loss functions evaluate predictions with respect to true
  data, often to measure the divergence between a model's
  representation of the data-generating distribution and the
  true representation of the data-generating distribution.

  Each loss function is implemented as an element-wise function
  measuring the loss with respect to the input target `y_true`
  and input prediction `y_pred`. As an example, the `mean_squared_error/2`
  loss function produces a tensor whose values are the mean squared
  error between targets and predictions:

      iex> y_true = Nx.tensor([[0.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[1.0, 1.0], [1.0, 0.0]], type: {:f, 32})
      iex> Axon.Losses.mean_squared_error(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.5, 0.5]
      >

  It's common to compute the loss across an entire minibatch.
  You can easily do so by composing one of these loss functions
  with a reduction such as `Nx.sum` or `Nx.mean`:

      iex> y_true = Nx.tensor([[0.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[1.0, 1.0], [1.0, 0.0]], type: {:f, 32})
      iex> losses = Axon.Losses.mean_squared_error(y_true, y_pred)
      iex> Nx.mean(losses)
      #Nx.Tensor<
        f32
        0.5
      >

  You can even compose loss functions:

      defn my_strange_loss(y_true, y_pred) do
        y_true
        |> Axon.mean_squared_error(y_pred)
        |> Axon.binary_cross_entropy(y_pred)
        |> Nx.sum()
      end

  Or, more commonly, you can combine loss functions with penalties for
  regularization:

      defn regularized_loss(params, y_true, y_pred) do
        loss = Axon.mean_squared_error(y_true, y_pred)
        penalty = l2_penalty(params)
        Nx.sum(loss) + penalty
      end

  All of the functions in this module are implemented as
  numerical functions and can be JIT or AOT compiled with
  any supported `Nx` compiler.

  """

  import Nx.Defn
  import Axon.Shared

  @doc ~S"""
  Binary cross-entropy loss function.

  $$-\frac{1}{2}(\hat{y_i} \cdot \log(y_i) + (1 - \hat{y_i}) \cdot \log(1 - y_i))$$

  Binary cross-entropy is most commonly used when there are
  two label classes in classification problems. This function
  expects the targets `y_true` to be a one-hot encoded
  representation of the labels.

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0, 1], [1, 0], [1, 0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[0.6811, 0.5565], [0.6551, 0.4551], [0.5422, 0.2648]], type: {:f, 32})
      iex> Axon.Losses.binary_cross_entropy(y_true, y_pred)
      #Nx.Tensor<
        f32[3]
        [0.8644828796386719, 0.5150601863861084, 0.4598664939403534]
      >
  """
  defn binary_cross_entropy(y_true, y_pred) do
    assert_shape!(y_true, y_pred)
    Nx.mean(-xlogy(y_true, y_pred) - xlogy(1 - y_true, 1 - y_pred), axes: [-1])
  end

  @doc ~S"""
  Categorical cross-entropy loss function.

  $$-\sum_i^C \hat{y_i} \cdot \log(y_i)$$

  Categorical cross-entropy is most commonly used when there are
  more than two label classes in classification problems. This
  function expects the targets `y_true` to be a one-hot encoded
  representation of the labels.

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0, 1, 0], [0, 0, 1]], type: {:s, 8})
      iex> y_pred = Nx.tensor([[0.05, 0.95, 0], [0.1, 0.8, 0.1]], type: {:f, 32})
      iex> Axon.Losses.categorical_cross_entropy(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.051293306052684784, 2.3025851249694824]
      >
  """
  defn categorical_cross_entropy(y_true, y_pred) do
    assert_shape!(y_true, y_pred)
    -Nx.sum(xlogy(y_true, y_pred), axes: [-1])
  end

  @doc ~S"""
  Categorical hinge loss function.

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[1, 0, 0], [0, 0, 1]], type: {:s, 8})
      iex> y_pred = Nx.tensor([[0.05300799, 0.21617081, 0.68642382], [0.3754382 , 0.08494169, 0.13442067]], type: {:f, 32})
      iex> Axon.Losses.categorical_hinge(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [1.6334158182144165, 1.2410175800323486]
      >
  """
  defn categorical_hinge(y_true, y_pred) do
    pos = Nx.sum(y_true * y_pred, axes: [-1])
    neg = Nx.reduce_max((1 - y_true) * y_pred, axes: [-1])
    Nx.max(neg - pos + 1, 0.0)
  end

  @doc ~S"""
  Hinge loss function.

  $$\frac{1}{C}\max_i(1 - \hat{y_i} * y_i, 0)$$

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[ 1,  1, -1], [ 1,  1, -1]], type: {:s, 8})
      iex> y_pred = Nx.tensor([[0.45440044, 0.31470688, 0.67920924], [0.24311459, 0.93466766, 0.10914676]], type: {:f, 32})
      iex> Axon.Losses.hinge(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.9700339436531067, 0.6437881588935852]
      >
  """
  defn hinge(y_true, y_pred) do
    assert_shape!(y_true, y_pred)
    Nx.mean(Nx.max(1.0 - y_true * y_pred, 0.0), axes: [-1])
  end

  @doc ~S"""
  Kullback-Leibler divergence loss function.

  $$\sum_i^C \hat{y_i} \cdot \log(\frac{\hat{y_i}}{y_i})$$

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0, 1], [0, 0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[0.6, 0.4], [0.4, 0.6]], type: {:f, 32})
      iex> Axon.Losses.kl_divergence(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.916289210319519, -3.080907390540233e-6]
      >
  """
  defn kl_divergence(y_true, y_pred) do
    assert_shape!(y_true, y_pred)

    epsilon = 1.0e-7

    y_true =
      Nx.clip(
        y_true,
        Nx.tensor(epsilon, type: Nx.type(y_true)),
        Nx.tensor(1, type: Nx.type(y_true))
      )

    y_pred =
      Nx.clip(
        y_pred,
        Nx.tensor(epsilon, type: Nx.type(y_pred)),
        Nx.tensor(1, type: Nx.type(y_pred))
      )

    Nx.sum(y_true * Nx.log(y_true / y_pred), axes: [-1])
  end

  @doc ~S"""
  Logarithmic-Hyperbolic Cosine loss function.

  $$\frac{1}{C} \sum_i^C (\hat{y_i} - y_i) + \log(1 + e^{-2(\hat{y_i} - y_i)}) - \log(2)$$

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[1.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> Axon.Losses.log_cosh(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.2168903946876526, 0.0]
      >
  """
  defn log_cosh(y_true, y_pred) do
    assert_shape!(y_true, y_pred)

    x = y_pred - y_true

    softplus_x =
      x + Nx.log1p(Nx.exp(Nx.tensor(-2.0, type: Nx.type(x)) * x)) -
        Nx.log(Nx.tensor(2.0, type: Nx.type(x)))

    Nx.mean(softplus_x, axes: [-1])
  end

  @doc """
  Margin ranking loss function.

  ## Examples

      iex> y_true = Nx.tensor([1.0, 1.0, 1.0], type: {:f, 32})
      iex> y_pred1 = Nx.tensor([0.6934, -0.7239,  1.1954], type: {:f, 32})
      iex> y_pred2 = Nx.tensor([-0.4691, 0.2670, -1.7452], type: {:f, 32})
      iex> Axon.Losses.margin_ranking(y_true, y_pred1, y_pred2)
      #Nx.Tensor<
        f32[3]
        [0.0, 0.9909000396728516, 0.0]
      >
  """
  defn margin_ranking(y_true, y_pred1, y_pred2, opts \\ []) do
    opts = keyword!(opts, margin: 0.0)
    Nx.max(0, Nx.negate(y_true) * (y_pred1 - y_pred2) + opts[:margin])
  end

  @doc """
  Soft margin loss function.

  ## Examples

      iex> y_true = Nx.tensor([[-1.0, 1.0,  1.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[0.2953, -0.1709, 0.9486]], type: {:f, 32})
      iex> Axon.Losses.soft_margin(y_true, y_pred)
      #Nx.Tensor<
        f32[3]
        [0.851658046245575, 0.7822436094284058, 0.3273470401763916]
      >
  """
  defn soft_margin(y_true, y_pred) do
    Nx.sum(Nx.log1p(Nx.exp(Nx.negate(y_true) * y_pred)), axes: [0])
  end

  @doc ~S"""
  Mean-absolute error loss function.

  $$\sum_i |\hat{y_i} - y_i|$$

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[1.0, 1.0], [1.0, 0.0]], type: {:f, 32})
      iex> Axon.Losses.mean_absolute_error(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.5, 0.5]
      >
  """
  defn mean_absolute_error(y_true, y_pred) do
    assert_shape!(y_true, y_pred)

    Nx.mean(Nx.abs(y_true - y_pred), axes: [-1])
  end

  @doc ~S"""
  Mean-squared error loss function.

  $$\sum_i (\hat{y_i} - y_i)^2$$

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[1.0, 1.0], [1.0, 0.0]], type: {:f, 32})
      iex> Axon.Losses.mean_squared_error(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.5, 0.5]
      >
  """
  defn mean_squared_error(y_true, y_pred) do
    assert_shape!(y_true, y_pred)

    Nx.mean(Nx.power(y_true - y_pred, 2), axes: [-1])
  end

  @doc ~S"""
  Poisson loss function.

  $$ \frac{1}{C} \sum_i^C y_i - (\hat{y_i} \cdot \log(y_i))$$\

  ## Argument Shapes

    * `y_true` - $\(d_0, d_1, ..., d_n\)$
    * `y_pred` - $\(d_0, d_1, ..., d_n\)$

  ## Examples

      iex> y_true = Nx.tensor([[0.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> y_pred = Nx.tensor([[1.0, 1.0], [0.0, 0.0]], type: {:f, 32})
      iex> Axon.Losses.poisson(y_true, y_pred)
      #Nx.Tensor<
        f32[2]
        [0.9999999403953552, 0.0]
      >
  """
  defn poisson(y_true, y_pred) do
    assert_shape!(y_true, y_pred)

    output_type =
      transform({Nx.type(y_true), Nx.type(y_pred)}, &Nx.Type.merge(elem(&1, 0), elem(&1, 1)))

    epsilon = Nx.tensor(1.0e-7, type: output_type)
    Nx.mean(y_pred - y_true * Nx.log(y_pred + epsilon), axes: [-1])
  end
end