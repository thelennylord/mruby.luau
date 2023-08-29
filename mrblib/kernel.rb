module Kernel
  def puts(*args)
    new_args = args.map { |x| x.to_s }
    echo(*new_args)
  end
end